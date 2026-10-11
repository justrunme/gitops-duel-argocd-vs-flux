'use strict';

const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const {
  validateResourceName,
  validateNamespace,
  validateRepoUrl,
  validateAppPath,
} = require('./lib/validation');
const k8sLib = require('./lib/k8s');
const { fetchGitManifests } = require('./lib/git-manifests');

function parseCorsOrigins() {
  const raw = process.env.CORS_ORIGINS;
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return [];
  }
  return String(raw)
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function apiToken() {
  const t = process.env.UI_API_TOKEN;
  if (t === undefined || t === null) return '';
  return String(t);
}

function requireApiAuth(req, res, next) {
  const expected = apiToken();
  if (!expected) {
    // Misconfiguration in production: refuse rather than open the API
    if (process.env.NODE_ENV === 'production') {
      return res.status(503).json({ error: 'API token not configured' });
    }
    return next();
  }
  const hdr = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(hdr);
  if (!m || m[1] !== expected) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  return next();
}

function createApp(options = {}) {
  const app = express();
  const customApi = options.customApi || null;
  const gitFetch = options.gitFetch || fetchGitManifests;
  const getClients =
    options.getClients ||
    (() => {
      if (customApi) return { custom: customApi };
      return k8sLib.createClients();
    });

  app.disable('x-powered-by');
  app.use(helmet());
  app.use(express.json({ limit: '32kb' }));

  const corsOrigins = parseCorsOrigins();
  app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && corsOrigins.includes(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
      res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
      res.setHeader(
        'Access-Control-Allow-Headers',
        'Origin, X-Requested-With, Content-Type, Accept, Authorization'
      );
    }
    if (req.method === 'OPTIONS') {
      return res.sendStatus(204);
    }
    return next();
  });

  const limiter = rateLimit({
    windowMs: Number(process.env.RATE_LIMIT_WINDOW_MS || 60_000),
    max: Number(process.env.RATE_LIMIT_MAX || 60),
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests' },
  });
  app.use('/api/', limiter);
  app.use('/api/', requireApiAuth);

  app.get('/', (_req, res) => {
    res.type('text').send('UI Backend is running!');
  });

  app.get('/healthz', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/api/argocd/applications', async (_req, res) => {
    try {
      const { custom } = getClients();
      const items = await k8sLib.listArgoApplications(custom);
      res.json(items);
    } catch (err) {
      console.error('list Argo applications:', err.message);
      res.status(500).json({ error: 'failed to list Argo CD applications' });
    }
  });

  app.get('/api/flux/kustomizations', async (_req, res) => {
    try {
      const { custom } = getClients();
      const body = await k8sLib.listFluxKustomizations(custom);
      res.json(body);
    } catch (err) {
      console.error('list Flux kustomizations:', err.message);
      res.status(500).json({ error: 'failed to list Flux kustomizations' });
    }
  });

  app.get('/api/argocd/application/:name/manifests', async (req, res) => {
    const nameCheck = validateResourceName(req.params.name);
    if (!nameCheck.ok) {
      return res.status(400).json({ error: nameCheck.error });
    }
    const nsCheck = validateNamespace(req.query.namespace || 'argocd');
    if (!nsCheck.ok) {
      return res.status(400).json({ error: nsCheck.error });
    }
    try {
      const { custom } = getClients();
      const obj = await k8sLib.getArgoApplication(custom, nameCheck.value, nsCheck.value);
      res.type('text/yaml').send(k8sLib.toYaml(obj));
    } catch (err) {
      const code = err.statusCode || err.code || 500;
      if (code === 404) {
        return res.status(404).json({ error: 'application not found' });
      }
      console.error('get Argo application:', err.message);
      res.status(500).json({ error: 'failed to get Argo CD application' });
    }
  });

  app.get('/api/flux/kustomization/:name/manifests', async (req, res) => {
    const nameCheck = validateResourceName(req.params.name);
    if (!nameCheck.ok) {
      return res.status(400).json({ error: nameCheck.error });
    }
    const nsCheck = validateNamespace(req.query.namespace || 'flux-system');
    if (!nsCheck.ok) {
      return res.status(400).json({ error: nsCheck.error });
    }
    try {
      const { custom } = getClients();
      const obj = await k8sLib.getFluxKustomization(custom, nameCheck.value, nsCheck.value);
      res.type('text/yaml').send(k8sLib.toYaml(obj));
    } catch (err) {
      const code = err.statusCode || err.code || 500;
      if (code === 404) {
        return res.status(404).json({ error: 'kustomization not found' });
      }
      console.error('get Flux kustomization:', err.message);
      res.status(500).json({ error: 'failed to get Flux kustomization' });
    }
  });

  app.get('/api/git/manifests', async (req, res) => {
    const repoCheck = validateRepoUrl(req.query.repoUrl);
    if (!repoCheck.ok) {
      return res.status(400).json({ error: repoCheck.error });
    }
    const pathCheck = validateAppPath(req.query.appPath);
    if (!pathCheck.ok) {
      return res.status(400).json({ error: pathCheck.error });
    }
    try {
      const manifests = await gitFetch(repoCheck.value, pathCheck.value);
      res.json(manifests);
    } catch (err) {
      const status = err.statusCode || 500;
      if (status === 400) {
        return res.status(400).json({ error: err.message });
      }
      console.error('git manifests:', err.message);
      res.status(500).json({ error: 'failed to fetch git manifests' });
    }
  });

  return app;
}

module.exports = { createApp, parseCorsOrigins, requireApiAuth, apiToken };
