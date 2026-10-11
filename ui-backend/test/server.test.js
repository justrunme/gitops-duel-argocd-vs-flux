'use strict';

const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.RATE_LIMIT_MAX = '1000';
process.env.CORS_ORIGINS = 'https://ui.example.com';

const { createApp } = require('../app');

function mockCustomApi() {
  return {
    async listClusterCustomObject() {
      return { items: [] };
    },
    async getNamespacedCustomObject({ name, namespace }) {
      return {
        apiVersion: 'argoproj.io/v1alpha1',
        kind: 'Application',
        metadata: { name, namespace },
        spec: {},
        status: {},
      };
    },
  };
}

describe('HTTP API input hardening', () => {
  let app;

  before(() => {
    app = createApp({
      customApi: mockCustomApi(),
      gitFetch: async () => ({ 'deployment.yaml': 'kind: Deployment\n' }),
    });
  });

  const maliciousNames = [
    'foo;rm -rf /',
    'foo;id',
    '$(whoami)',
    '`reboot`',
    '../etc',
    'foo/../bar',
    'UPPER',
    'has_underscore',
  ];

  for (const name of maliciousNames) {
    it(`GET /api/argocd/application/:name rejects ${JSON.stringify(name)}`, async () => {
      const res = await request(app).get(
        `/api/argocd/application/${encodeURIComponent(name)}/manifests?namespace=argocd`
      );
      assert.equal(res.status, 400);
      assert.match(String(res.body.error || ''), /invalid|DNS-1123|allowlist/i);
    });

    it(`GET /api/flux/kustomization/:name rejects ${JSON.stringify(name)}`, async () => {
      const res = await request(app).get(
        `/api/flux/kustomization/${encodeURIComponent(name)}/manifests?namespace=flux-system`
      );
      assert.equal(res.status, 400);
      assert.match(String(res.body.error || ''), /invalid|DNS-1123|allowlist/i);
    });
  }

  it('rejects malicious namespace query', async () => {
    const res = await request(app).get(
      '/api/argocd/application/nginx-app/manifests?namespace=argocd%3B%20rm%20-rf%20%2F'
    );
    assert.equal(res.status, 400);
  });

  it('rejects path traversal namespace', async () => {
    const res = await request(app).get(
      '/api/argocd/application/nginx-app/manifests?namespace=..%2Fkube-system'
    );
    assert.equal(res.status, 400);
  });

  it('rejects non-allowlisted namespace', async () => {
    const res = await request(app).get(
      '/api/argocd/application/nginx-app/manifests?namespace=kube-system'
    );
    assert.equal(res.status, 400);
    assert.match(res.body.error, /allowlist/i);
  });

  it('accepts valid Argo application name', async () => {
    const res = await request(app).get(
      '/api/argocd/application/nginx-app/manifests?namespace=argocd'
    );
    assert.equal(res.status, 200);
    assert.match(res.text, /nginx-app/);
  });

  it('rejects git clone injection via repoUrl', async () => {
    const res = await request(app).get('/api/git/manifests').query({
      repoUrl: 'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git; rm -rf /',
      appPath: 'apps/argocd/nginx',
    });
    assert.equal(res.status, 400);
  });

  it('rejects $(...) in repoUrl', async () => {
    const res = await request(app).get('/api/git/manifests').query({
      repoUrl: 'https://github.com/justrunme/$(whoami)/x.git',
      appPath: 'apps/argocd/nginx',
    });
    assert.equal(res.status, 400);
  });

  it('rejects path traversal in appPath', async () => {
    const res = await request(app).get('/api/git/manifests').query({
      repoUrl: 'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
      appPath: 'apps/argocd/../../../etc/passwd',
    });
    assert.equal(res.status, 400);
    assert.match(res.body.error, /traversal|allowlist|forbidden/i);
  });

  it('rejects non-allowlisted appPath', async () => {
    const res = await request(app).get('/api/git/manifests').query({
      repoUrl: 'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
      appPath: 'secrets/prod',
    });
    assert.equal(res.status, 400);
  });

  it('serves allowlisted git manifests without shell', async () => {
    const res = await request(app).get('/api/git/manifests').query({
      repoUrl: 'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
      appPath: 'apps/argocd/nginx',
    });
    assert.equal(res.status, 200);
    assert.ok(res.body['deployment.yaml']);
  });

  it('restricts CORS to configured origins', async () => {
    const allowed = await request(app)
      .get('/healthz')
      .set('Origin', 'https://ui.example.com');
    assert.equal(allowed.headers['access-control-allow-origin'], 'https://ui.example.com');

    const denied = await request(app)
      .get('/healthz')
      .set('Origin', 'https://evil.example');
    assert.equal(denied.headers['access-control-allow-origin'], undefined);
  });

  it('sets helmet security headers', async () => {
    const res = await request(app).get('/healthz');
    assert.ok(res.headers['x-content-type-options']);
    assert.equal(res.headers['x-powered-by'], undefined);
  });
});
