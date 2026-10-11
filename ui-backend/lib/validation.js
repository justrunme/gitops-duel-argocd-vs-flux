'use strict';

// DNS-1123 label: lowercase alphanumeric, '-' allowed in the middle, 1–63 chars
const DNS1123_LABEL = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/;
const DNS1123_MAX = 63;

const DEFAULT_ALLOWED_NAMESPACES = Object.freeze([
  'argocd',
  'flux-system',
  'argocd-demo',
  'flux-demo',
  'default',
]);

const DEFAULT_ALLOWED_REPO_URLS = Object.freeze([
  'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git',
  'https://github.com/justrunme/gitops-duel-argocd-vs-flux',
]);

const DEFAULT_ALLOWED_APP_PATH_PREFIXES = Object.freeze([
  'apps/argocd/',
  'apps/flux/',
]);

function parseCsvEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return [...fallback];
  }
  return String(raw)
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function allowedNamespaces() {
  return parseCsvEnv('ALLOWED_NAMESPACES', DEFAULT_ALLOWED_NAMESPACES);
}

function allowedRepoUrls() {
  return parseCsvEnv('ALLOWED_REPO_URLS', DEFAULT_ALLOWED_REPO_URLS);
}

function allowedAppPathPrefixes() {
  return parseCsvEnv('ALLOWED_APP_PATH_PREFIXES', DEFAULT_ALLOWED_APP_PATH_PREFIXES);
}

function isDns1123Label(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > DNS1123_MAX) {
    return false;
  }
  return DNS1123_LABEL.test(value);
}

function validateResourceName(name) {
  if (!isDns1123Label(name)) {
    return { ok: false, error: 'invalid resource name (DNS-1123 label required)' };
  }
  return { ok: true, value: name };
}

function validateNamespace(namespace) {
  if (!isDns1123Label(namespace)) {
    return { ok: false, error: 'invalid namespace (DNS-1123 label required)' };
  }
  const allow = allowedNamespaces();
  if (!allow.includes(namespace)) {
    return { ok: false, error: 'namespace not in allowlist' };
  }
  return { ok: true, value: namespace };
}

function normalizeRepoUrl(repoUrl) {
  if (typeof repoUrl !== 'string') return '';
  return repoUrl.trim().replace(/\/+$/, '');
}

function validateRepoUrl(repoUrl) {
  const normalized = normalizeRepoUrl(repoUrl);
  if (!normalized) {
    return { ok: false, error: 'repoUrl is required' };
  }
  // Reject shell metacharacters and traversal-style schemes
  if (/[;`$|&<>(){}]|\$\(|`/.test(normalized) || normalized.includes('..')) {
    return { ok: false, error: 'repoUrl contains forbidden characters' };
  }
  let parsed;
  try {
    parsed = new URL(normalized);
  } catch {
    return { ok: false, error: 'repoUrl must be a valid https URL' };
  }
  if (parsed.protocol !== 'https:') {
    return { ok: false, error: 'repoUrl must use https' };
  }
  const allow = allowedRepoUrls().map(normalizeRepoUrl);
  const candidates = [normalized, `${normalized}.git`];
  if (!candidates.some((c) => allow.includes(c) || allow.includes(c.replace(/\.git$/, '')))) {
    return { ok: false, error: 'repoUrl not in allowlist' };
  }
  return { ok: true, value: normalized };
}

function validateAppPath(appPath) {
  if (typeof appPath !== 'string' || appPath.trim() === '') {
    return { ok: false, error: 'appPath is required' };
  }
  const trimmed = appPath.trim().replace(/^\/+/, '');
  if (trimmed.includes('\0') || /[;`$|&<>(){}]|\$\(/.test(trimmed)) {
    return { ok: false, error: 'appPath contains forbidden characters' };
  }
  const segments = trimmed.split('/');
  if (segments.some((s) => s === '..' || s === '.' || s === '')) {
    return { ok: false, error: 'appPath must not contain path traversal segments' };
  }
  const prefixes = allowedAppPathPrefixes();
  if (!prefixes.some((p) => trimmed === p.replace(/\/$/, '') || trimmed.startsWith(p))) {
    return { ok: false, error: 'appPath not in allowlist' };
  }
  return { ok: true, value: trimmed };
}

module.exports = {
  DNS1123_LABEL,
  isDns1123Label,
  validateResourceName,
  validateNamespace,
  validateRepoUrl,
  validateAppPath,
  allowedNamespaces,
  allowedRepoUrls,
  allowedAppPathPrefixes,
  normalizeRepoUrl,
};
