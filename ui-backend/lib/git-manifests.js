'use strict';

const https = require('https');
const http = require('http');
const path = require('path');
const { URL } = require('url');
const { validateRepoUrl, validateAppPath, normalizeRepoUrl } = require('./validation');

const DEFAULT_ALLOWED_DOWNLOAD_HOSTS = Object.freeze([
  'api.github.com',
  'raw.githubusercontent.com',
  'objects.githubusercontent.com',
]);

const MAX_DOWNLOAD_BYTES = Number(process.env.GIT_MANIFEST_MAX_BYTES || 1_048_576); // 1 MiB
const MAX_REDIRECTS = 3;

function allowedDownloadHosts() {
  const raw = process.env.ALLOWED_DOWNLOAD_HOSTS;
  let hosts;
  if (!raw || !String(raw).trim()) {
    hosts = [...DEFAULT_ALLOWED_DOWNLOAD_HOSTS];
  } else {
    hosts = String(raw)
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean);
  }
  // Unit tests use a local fake HTTP server
  if (process.env.NODE_ENV === 'test') {
    for (const h of ['127.0.0.1', 'localhost']) {
      if (!hosts.includes(h)) hosts.push(h);
    }
  }
  return hosts;
}

function assertAllowedHost(hostname) {
  const host = String(hostname || '').toLowerCase();
  if (!allowedDownloadHosts().includes(host)) {
    const err = new Error(`download host not allowed: ${host}`);
    err.statusCode = 400;
    throw err;
  }
}

function encodePathSegments(posixPath) {
  return String(posixPath)
    .split('/')
    .map((seg) => encodeURIComponent(seg))
    .join('/');
}

function requestText(urlString, { redirectsLeft = MAX_REDIRECTS, headers = {}, expectJson = false } = {}) {
  return new Promise((resolve, reject) => {
    let url;
    try {
      url = new URL(urlString);
    } catch {
      reject(Object.assign(new Error('invalid URL'), { statusCode: 400 }));
      return;
    }
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      reject(Object.assign(new Error('only http(s) URLs allowed'), { statusCode: 400 }));
      return;
    }
    // Production fetches must be https; http allowed only for unit-test fake servers
    if (url.protocol === 'http:' && process.env.NODE_ENV !== 'test') {
      reject(Object.assign(new Error('only https URLs allowed'), { statusCode: 400 }));
      return;
    }
    assertAllowedHost(url.hostname);

    const transport = url.protocol === 'http:' ? http : https;
    const req = transport.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || undefined,
        path: `${url.pathname}${url.search}`,
        method: 'GET',
        headers: {
          'User-Agent': 'gitops-duel-ui-backend',
          Accept: expectJson ? 'application/vnd.github+json' : '*/*',
          ...headers,
        },
        timeout: 15000,
      },
      (res) => {
        if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          if (redirectsLeft <= 0) {
            reject(Object.assign(new Error('too many redirects'), { statusCode: 400 }));
            return;
          }
          let next;
          try {
            next = new URL(res.headers.location, url).toString();
          } catch {
            reject(Object.assign(new Error('invalid redirect location'), { statusCode: 400 }));
            return;
          }
          try {
            assertAllowedHost(new URL(next).hostname);
          } catch (err) {
            reject(err);
            return;
          }
          requestText(next, { redirectsLeft: redirectsLeft - 1, headers, expectJson }).then(resolve, reject);
          return;
        }

        const chunks = [];
        let total = 0;
        let aborted = false;
        res.on('data', (c) => {
          total += c.length;
          if (total > MAX_DOWNLOAD_BYTES) {
            aborted = true;
            req.destroy();
            reject(Object.assign(new Error(`response exceeds ${MAX_DOWNLOAD_BYTES} bytes`), { statusCode: 400 }));
            return;
          }
          chunks.push(c);
        });
        res.on('end', () => {
          if (aborted) return;
          const body = Buffer.concat(chunks).toString('utf8');
          if (res.statusCode && res.statusCode >= 400) {
            reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
            return;
          }
          if (expectJson) {
            try {
              resolve(JSON.parse(body));
            } catch (err) {
              reject(err);
            }
            return;
          }
          resolve(body);
        });
      }
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy(new Error('request timeout'));
    });
    req.end();
  });
}

function httpsGetJson(urlString, headers = {}) {
  return requestText(urlString, { headers, expectJson: true });
}

function httpsGetText(urlString) {
  return requestText(urlString, { expectJson: false });
}

function githubOwnerRepo(repoUrl) {
  const u = new URL(normalizeRepoUrl(repoUrl));
  const parts = u.pathname.replace(/^\//, '').replace(/\.git$/, '').split('/');
  if (parts.length < 2) {
    throw new Error('cannot parse owner/repo from repoUrl');
  }
  return { owner: parts[0], repo: parts[1] };
}

/**
 * Fetch directory manifests from an allowlisted GitHub repo via HTTPS API
 * (no shell, no git clone).
 */
async function fetchGitManifests(repoUrl, appPath, options = {}) {
  const repoCheck = validateRepoUrl(repoUrl);
  if (!repoCheck.ok) {
    const err = new Error(repoCheck.error);
    err.statusCode = 400;
    throw err;
  }
  const pathCheck = validateAppPath(appPath);
  if (!pathCheck.ok) {
    const err = new Error(pathCheck.error);
    err.statusCode = 400;
    throw err;
  }

  const ref = options.ref || process.env.GIT_MANIFESTS_REF || 'main';
  const { owner, repo } = githubOwnerRepo(repoCheck.value);
  const encodedPath = encodePathSegments(pathCheck.value);
  const apiBase = options.apiBase || 'https://api.github.com';
  const apiHost = new URL(apiBase).hostname;
  assertAllowedHost(apiHost);
  const apiUrl =
    `${apiBase.replace(/\/$/, '')}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}` +
    `/contents/${encodedPath}?ref=${encodeURIComponent(ref)}`;

  const listing = await httpsGetJson(apiUrl);
  if (!Array.isArray(listing)) {
    const err = new Error('appPath did not resolve to a directory');
    err.statusCode = 400;
    throw err;
  }

  const manifests = {};
  const baseResolved = path.posix.normalize(pathCheck.value);

  for (const entry of listing) {
    if (entry.type !== 'file') continue;
    const name = entry.name;
    if (!/\.(ya?ml|yml|json)$/i.test(name)) continue;

    const entryPath = path.posix.normalize(entry.path || `${pathCheck.value}/${name}`);
    if (entryPath.includes('..')) continue;
    if (!entryPath.startsWith(`${baseResolved}/`)) continue;

    if (entry.download_url) {
      let dl;
      try {
        dl = new URL(entry.download_url);
      } catch {
        continue;
      }
      assertAllowedHost(dl.hostname);
      manifests[name] = await httpsGetText(entry.download_url);
    }
  }

  return manifests;
}

module.exports = {
  fetchGitManifests,
  githubOwnerRepo,
  encodePathSegments,
  allowedDownloadHosts,
  assertAllowedHost,
  MAX_DOWNLOAD_BYTES,
};
