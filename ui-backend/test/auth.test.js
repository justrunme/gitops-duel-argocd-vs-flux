'use strict';

const { describe, it, before, after, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const ORIG_ENV = { ...process.env };

function restoreEnv() {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIG_ENV)) delete process.env[key];
  }
  for (const [key, value] of Object.entries(ORIG_ENV)) {
    process.env[key] = value;
  }
}

function loadApp() {
  delete require.cache[require.resolve('../app')];
  return require('../app');
}

describe('API auth middleware and startup', () => {
  after(() => {
    restoreEnv();
    delete require.cache[require.resolve('../app')];
  });

  describe('assertAuthConfigured (startup)', () => {
    afterEach(() => {
      restoreEnv();
      delete require.cache[require.resolve('../app')];
    });

    it('throws when no token is configured and AUTH_DISABLED is not set', () => {
      delete process.env.UI_API_TOKEN;
      delete process.env.AUTH_DISABLED;
      process.env.NODE_ENV = 'development';
      const { assertAuthConfigured } = loadApp();
      assert.throws(
        () => assertAuthConfigured(),
        /UI_API_TOKEN is required/
      );
    });

    it('throws for empty token even when NODE_ENV is not production (negative)', () => {
      process.env.UI_API_TOKEN = '';
      delete process.env.AUTH_DISABLED;
      process.env.NODE_ENV = 'development';
      const { assertAuthConfigured } = loadApp();
      assert.throws(
        () => assertAuthConfigured(),
        /UI_API_TOKEN is required/
      );
    });

    it('does not throw when UI_API_TOKEN is set', () => {
      process.env.UI_API_TOKEN = 'startup-ok-token';
      delete process.env.AUTH_DISABLED;
      const { assertAuthConfigured } = loadApp();
      assert.doesNotThrow(() => assertAuthConfigured());
    });

    it('allows AUTH_DISABLED=true without token and warns loudly', () => {
      delete process.env.UI_API_TOKEN;
      process.env.AUTH_DISABLED = 'true';
      const warnings = [];
      const origWarn = console.warn;
      console.warn = (...args) => {
        warnings.push(args.join(' '));
      };
      try {
        const { assertAuthConfigured } = loadApp();
        assert.doesNotThrow(() => assertAuthConfigured());
      } finally {
        console.warn = origWarn;
      }
      assert.ok(
        warnings.some((w) => /AUTH_DISABLED=true/i.test(w)),
        'expected loud AUTH_DISABLED warning'
      );
    });
  });

  describe('requireApiAuth (requests)', () => {
    let createApp;
    let app;
    const token = 'unit-test-bearer-token';

    before(() => {
      restoreEnv();
      process.env.NODE_ENV = 'test';
      process.env.RATE_LIMIT_MAX = '1000';
      process.env.UI_API_TOKEN = token;
      delete process.env.AUTH_DISABLED;
      ({ createApp } = loadApp());
      app = createApp({
        customApi: {
          async listNamespacedRules() {
            return { items: [] };
          },
          async listNamespacedCustomObject() {
            return { items: [] };
          },
        },
        gitFetch: async () => ({}),
      });
    });

    after(() => {
      restoreEnv();
      delete require.cache[require.resolve('../app')];
    });

    it('returns 401 when Authorization header is missing (negative)', async () => {
      const res = await request(app).get('/api/argocd/applications');
      assert.equal(res.status, 401);
      assert.equal(res.body.error, 'unauthorized');
    });

    it('returns 401 when bearer token is wrong (negative)', async () => {
      const res = await request(app)
        .get('/api/argocd/applications')
        .set({ Authorization: 'Bearer wrong-token' });
      assert.equal(res.status, 401);
      assert.equal(res.body.error, 'unauthorized');
    });

    it('returns 200 when bearer token is correct', async () => {
      const res = await request(app)
        .get('/api/argocd/applications')
        .set({ Authorization: `Bearer ${token}` });
      assert.equal(res.status, 200);
      assert.ok(Array.isArray(res.body));
    });

    it('keeps /healthz open without a token', async () => {
      const res = await request(app).get('/healthz');
      assert.equal(res.status, 200);
      assert.equal(res.body.status, 'ok');
    });
  });

  describe('NODE_ENV must not open the API without a token (negative)', () => {
    afterEach(() => {
      restoreEnv();
      delete require.cache[require.resolve('../app')];
    });

    it('rejects unauthenticated /api when token empty and NODE_ENV=development', async () => {
      process.env.UI_API_TOKEN = '';
      delete process.env.AUTH_DISABLED;
      process.env.NODE_ENV = 'development';
      process.env.RATE_LIMIT_MAX = '1000';
      const { createApp } = loadApp();
      const app = createApp({
        customApi: {
          async listNamespacedCustomObject() {
            return { items: [] };
          },
        },
      });
      const res = await request(app).get('/api/argocd/applications');
      // Must not call next() / 200 — formerly open in non-production.
      assert.notEqual(res.status, 200);
      assert.ok(
        res.status === 401 || res.status === 503,
        `expected 401 or 503, got ${res.status}`
      );
    });
  });

  describe('misconfigured runtime without startup guard (negative)', () => {
    afterEach(() => {
      restoreEnv();
      delete require.cache[require.resolve('../app')];
    });

    it('returns 503 when token missing and AUTH_DISABLED unset', async () => {
      delete process.env.UI_API_TOKEN;
      delete process.env.AUTH_DISABLED;
      process.env.NODE_ENV = 'test';
      process.env.RATE_LIMIT_MAX = '1000';
      const { createApp } = loadApp();
      const app = createApp({
        customApi: {
          async listNamespacedCustomObject() {
            return { items: [] };
          },
        },
      });
      const res = await request(app).get('/api/argocd/applications');
      assert.equal(res.status, 503);
      assert.match(String(res.body.error || ''), /not configured/i);
    });
  });
});
