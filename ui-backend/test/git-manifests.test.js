'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');

process.env.NODE_ENV = 'test';

const {
  fetchGitManifests,
  encodePathSegments,
  assertAllowedHost,
  MAX_DOWNLOAD_BYTES,
} = require('../lib/git-manifests');

describe('git-manifests HTTPS fetch (fake HTTP server)', () => {
  let server;
  let baseUrl;
  let hits;

  before(async () => {
    hits = [];
    server = http.createServer((req, res) => {
      hits.push({ url: req.url, host: req.headers.host });
      const u = new URL(req.url, 'http://127.0.0.1');

      if (u.pathname === '/repos/justrunme/gitops-duel-argocd-vs-flux/contents/apps/argocd/nginx') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify([
            {
              type: 'file',
              name: 'deployment.yaml',
              path: 'apps/argocd/nginx/deployment.yaml',
              download_url: `${baseUrl}/raw/deployment.yaml`,
            },
            {
              type: 'file',
              name: 'notes.txt',
              path: 'apps/argocd/nginx/notes.txt',
              download_url: `${baseUrl}/raw/notes.txt`,
            },
          ])
        );
        return;
      }

      if (u.pathname === '/repos/justrunme/gitops-duel-argocd-vs-flux/contents/apps/argocd/redir') {
        res.writeHead(302, { Location: `${baseUrl}/evil-redirect` });
        res.end();
        return;
      }

      if (u.pathname === '/evil-redirect') {
        // Would be reached only if redirect host checks failed
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end('[]');
        return;
      }

      if (u.pathname === '/repos/justrunme/gitops-duel-argocd-vs-flux/contents/apps/argocd/badhost') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify([
            {
              type: 'file',
              name: 'deployment.yaml',
              path: 'apps/argocd/badhost/deployment.yaml',
              download_url: 'https://evil.example/steal.yaml',
            },
          ])
        );
        return;
      }

      if (u.pathname === '/repos/justrunme/gitops-duel-argocd-vs-flux/contents/apps/argocd/big') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify([
            {
              type: 'file',
              name: 'deployment.yaml',
              path: 'apps/argocd/big/deployment.yaml',
              download_url: `${baseUrl}/raw/big.yaml`,
            },
          ])
        );
        return;
      }

      if (u.pathname === '/raw/deployment.yaml') {
        res.writeHead(200, { 'Content-Type': 'text/yaml' });
        res.end('apiVersion: apps/v1\nkind: Deployment\n');
        return;
      }

      if (u.pathname === '/raw/notes.txt') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('ignored');
        return;
      }

      if (u.pathname === '/raw/big.yaml') {
        res.writeHead(200, { 'Content-Type': 'text/yaml' });
        // Stream more than MAX_DOWNLOAD_BYTES
        const chunk = Buffer.alloc(64 * 1024, 0x61);
        let sent = 0;
        const target = MAX_DOWNLOAD_BYTES + chunk.length;
        const writeMore = () => {
          while (sent < target) {
            const ok = res.write(chunk);
            sent += chunk.length;
            if (!ok) {
              res.once('drain', writeMore);
              return;
            }
          }
          res.end();
        };
        writeMore();
        return;
      }

      if (u.pathname.includes('apps%2Fargocd%2Fnginx')) {
        // Path must be segment-encoded, not one blob — this would mean wrong encoding
        res.writeHead(404);
        res.end('bad encoding');
        return;
      }

      res.writeHead(404);
      res.end('not found');
    });

    await new Promise((resolve) => {
      server.listen(0, '127.0.0.1', resolve);
    });
    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
  });

  it('encodePathSegments URL-encodes each path segment', () => {
    assert.equal(encodePathSegments('apps/argocd/nginx'), 'apps/argocd/nginx');
    assert.equal(encodePathSegments('apps/argocd/a b'), 'apps/argocd/a%20b');
  });

  it('rejects non-allowlisted download hosts', () => {
    assert.throws(() => assertAllowedHost('evil.example'), /not allowed/);
  });

  it('fetches yaml manifests via fake API and checks download_url host', async () => {
    const manifests = await fetchGitManifests(
      'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
      'apps/argocd/nginx',
      { apiBase: baseUrl, ref: 'main' }
    );
    assert.ok(manifests['deployment.yaml']);
    assert.match(manifests['deployment.yaml'], /kind: Deployment/);
    assert.equal(manifests['notes.txt'], undefined);
    // contents path used segment encoding under /contents/apps/argocd/nginx
    assert.ok(
      hits.some((h) => h.url.includes('/contents/apps/argocd/nginx')),
      `expected encoded path hit, got ${JSON.stringify(hits)}`
    );
  });

  it('rejects listing whose download_url host is not allowlisted', async () => {
    // Monkey-patch by hitting badhost directory — validateAppPath only allows apps/argocd/*
    // Use apps/argocd/nginx path but we need badhost — allow apps/argocd/badhost via prefix apps/argocd/
    await assert.rejects(
      () =>
        fetchGitManifests(
          'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
          'apps/argocd/badhost',
          { apiBase: baseUrl, ref: 'main' }
        ),
      (err) => /not allowed|evil/i.test(String(err.message))
    );
  });

  it('rejects redirects to a disallowed host', async () => {
    // Redirect from allowlisted localhost to... we redirect to same host /evil-redirect which IS allowed.
    // Simulate cross-host by returning Location to https://evil.example/
    // Replace handler temporarily via a second request path:
    // Re-bind: close and... easier to assert assertAllowedHost on redirect in a dedicated micro-server.
    const redirects = [];
    const s2 = http.createServer((req, res) => {
      redirects.push(req.url);
      if (req.url.startsWith('/repos/')) {
        res.writeHead(302, { Location: 'https://evil.example/steal' });
        res.end();
        return;
      }
      res.writeHead(404);
      res.end();
    });
    await new Promise((r) => s2.listen(0, '127.0.0.1', r));
    const port = s2.address().port;
    const apiBase = `http://127.0.0.1:${port}`;
    try {
      await assert.rejects(
        () =>
          fetchGitManifests(
            'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
            'apps/argocd/nginx',
            { apiBase, ref: 'main' }
          ),
        (err) => /not allowed/i.test(String(err.message))
      );
    } finally {
      await new Promise((r) => s2.close(r));
    }
  });

  it('rejects oversized download bodies', async () => {
    await assert.rejects(
      () =>
        fetchGitManifests(
          'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
          'apps/argocd/big',
          { apiBase: baseUrl, ref: 'main' }
        ),
      (err) => /exceeds/i.test(String(err.message))
    );
  });
});
