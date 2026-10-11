'use strict';

const https = require('https');
const path = require('path');
const { URL } = require('url');
const { validateRepoUrl, validateAppPath, normalizeRepoUrl } = require('./validation');

function httpsGetJson(urlString, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlString);
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        method: 'GET',
        headers: {
          'User-Agent': 'gitops-duel-ui-backend',
          Accept: 'application/vnd.github+json',
          ...headers,
        },
        timeout: 15000,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const body = Buffer.concat(chunks).toString('utf8');
          if (res.statusCode && res.statusCode >= 400) {
            reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (err) {
            reject(err);
          }
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

function httpsGetText(urlString) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlString);
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        method: 'GET',
        headers: { 'User-Agent': 'gitops-duel-ui-backend' },
        timeout: 15000,
      },
      (res) => {
        // Follow one redirect (raw.githubusercontent.com sometimes redirects)
        if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          httpsGetText(res.headers.location).then(resolve, reject);
          res.resume();
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const body = Buffer.concat(chunks).toString('utf8');
          if (res.statusCode && res.statusCode >= 400) {
            reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
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
  const apiUrl =
    `https://api.github.com/repos/${owner}/${repo}/contents/${pathCheck.value}` +
    `?ref=${encodeURIComponent(ref)}`;

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

    // Containment: entry.path must stay under the validated appPath
    const entryPath = path.posix.normalize(entry.path || `${pathCheck.value}/${name}`);
    if (entryPath.includes('..') || !entryPath.startsWith(`${baseResolved}/`) && entryPath !== baseResolved) {
      continue;
    }
    if (!entryPath.startsWith(`${baseResolved}/`)) {
      continue;
    }

    if (entry.download_url) {
      manifests[name] = await httpsGetText(entry.download_url);
    }
  }

  return manifests;
}

module.exports = {
  fetchGitManifests,
  githubOwnerRepo,
};
