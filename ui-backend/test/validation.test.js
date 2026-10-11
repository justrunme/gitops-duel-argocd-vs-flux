'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  isDns1123Label,
  validateResourceName,
  validateNamespace,
  validateRepoUrl,
  validateAppPath,
} = require('../lib/validation');

describe('DNS-1123 validation', () => {
  it('accepts valid labels', () => {
    assert.equal(isDns1123Label('nginx-app'), true);
    assert.equal(isDns1123Label('a'), true);
    assert.equal(isDns1123Label('flux-system'), true);
  });

  it('rejects uppercase, underscores, empty, and overlong names', () => {
    assert.equal(isDns1123Label('Nginx'), false);
    assert.equal(isDns1123Label('nginx_app'), false);
    assert.equal(isDns1123Label(''), false);
    assert.equal(isDns1123Label('a'.repeat(64)), false);
    assert.equal(isDns1123Label('-bad'), false);
    assert.equal(isDns1123Label('bad-'), false);
  });
});

describe('malicious resource names', () => {
  const payloads = [
    'foo; rm -rf /',
    'foo;id',
    '$(whoami)',
    '`id`',
    'foo$(reboot)',
    '../../../etc/passwd',
    'foo|cat',
    'foo&&id',
    'foo\nid',
  ];

  for (const payload of payloads) {
    it(`rejects name ${JSON.stringify(payload)}`, () => {
      const result = validateResourceName(payload);
      assert.equal(result.ok, false);
    });
  }

  it('accepts nginx-app', () => {
    assert.equal(validateResourceName('nginx-app').ok, true);
  });
});

describe('malicious namespaces', () => {
  it('rejects shell injection and traversal', () => {
    assert.equal(validateNamespace('argocd; rm -rf /').ok, false);
    assert.equal(validateNamespace('$(id)').ok, false);
    assert.equal(validateNamespace('../kube-system').ok, false);
    assert.equal(validateNamespace('kube-system').ok, false); // not allowlisted
  });

  it('accepts allowlisted namespaces', () => {
    assert.equal(validateNamespace('argocd').ok, true);
    assert.equal(validateNamespace('flux-system').ok, true);
  });
});

describe('malicious repoUrl / appPath', () => {
  it('rejects shell metacharacters in repoUrl', () => {
    assert.equal(validateRepoUrl('https://evil.com/x.git; rm -rf /').ok, false);
    assert.equal(validateRepoUrl('https://evil.com/$(whoami).git').ok, false);
    assert.equal(validateRepoUrl('git://github.com/justrunme/gitops-duel-argocd-vs-flux.git').ok, false);
  });

  it('rejects non-allowlisted https repos', () => {
    assert.equal(validateRepoUrl('https://evil.example/repo.git').ok, false);
  });

  it('accepts allowlisted repo', () => {
    assert.equal(
      validateRepoUrl('https://github.com/justrunme/gitops-duel-argocd-vs-flux.git').ok,
      true
    );
  });

  it('rejects path traversal and shell injection in appPath', () => {
    assert.equal(validateAppPath('../secrets').ok, false);
    assert.equal(validateAppPath('apps/argocd/../../../etc').ok, false);
    assert.equal(validateAppPath('apps/argocd/nginx; rm -rf /').ok, false);
    assert.equal(validateAppPath('apps/argocd/$(id)').ok, false);
    assert.equal(validateAppPath('apps/evil/nginx').ok, false);
  });

  it('accepts allowlisted appPath', () => {
    assert.equal(validateAppPath('apps/argocd/nginx').ok, true);
    assert.equal(validateAppPath('apps/flux/nginx').ok, true);
  });
});
