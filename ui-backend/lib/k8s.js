'use strict';

const k8s = require('@kubernetes/client-node');
const yaml = require('js-yaml');
const { allowedNamespaces } = require('./validation');

const ARGO_GROUP = 'argoproj.io';
const ARGO_VERSION = 'v1alpha1';
const ARGO_PLURAL = 'applications';

const FLUX_GROUP = 'kustomize.toolkit.fluxcd.io';
const FLUX_VERSION = 'v1';
const FLUX_PLURAL = 'kustomizations';

function loadKubeConfig() {
  const kc = new k8s.KubeConfig();
  if (process.env.KUBECONFIG || process.env.KUBERNETES_SERVICE_HOST) {
    try {
      kc.loadFromDefault();
      return kc;
    } catch (err) {
      if (process.env.NODE_ENV !== 'test') {
        console.warn(`kubeconfig load warning: ${err.message}`);
      }
    }
  }
  try {
    kc.loadFromDefault();
  } catch {
    // empty
  }
  return kc;
}

function createClients(kc = loadKubeConfig()) {
  const custom = kc.makeApiClient(k8s.CustomObjectsApi);
  return { kc, custom };
}

function extractItems(res) {
  const body = res && res.items !== undefined ? res : res && res.body;
  return (body && body.items) || [];
}

async function listNamespaced(custom, { group, version, plural, namespaces }) {
  const nsList = namespaces || allowedNamespaces();
  const items = [];
  for (const namespace of nsList) {
    try {
      const res = await custom.listNamespacedCustomObject({
        group,
        version,
        plural,
        namespace,
      });
      items.push(...extractItems(res));
    } catch (err) {
      const code = err.statusCode || err.code;
      // Missing CRD/ns is skippable; other errors propagate
      if (code === 404) continue;
      throw err;
    }
  }
  return items;
}

async function listArgoApplications(custom, namespaces) {
  return listNamespaced(custom, {
    group: ARGO_GROUP,
    version: ARGO_VERSION,
    plural: ARGO_PLURAL,
    namespaces,
  });
}

async function listFluxKustomizations(custom, namespaces) {
  const items = await listNamespaced(custom, {
    group: FLUX_GROUP,
    version: FLUX_VERSION,
    plural: FLUX_PLURAL,
    namespaces,
  });
  return { items };
}

async function getArgoApplication(custom, name, namespace) {
  const res = await custom.getNamespacedCustomObject({
    group: ARGO_GROUP,
    version: ARGO_VERSION,
    plural: ARGO_PLURAL,
    namespace,
    name,
  });
  return res && res.metadata ? res : res.body;
}

async function getFluxKustomization(custom, name, namespace) {
  const res = await custom.getNamespacedCustomObject({
    group: FLUX_GROUP,
    version: FLUX_VERSION,
    plural: FLUX_PLURAL,
    namespace,
    name,
  });
  return res && res.metadata ? res : res.body;
}

function toYaml(obj) {
  return yaml.dump(obj, { lineWidth: -1, noRefs: true });
}

module.exports = {
  loadKubeConfig,
  createClients,
  listArgoApplications,
  listFluxKustomizations,
  getArgoApplication,
  getFluxKustomization,
  toYaml,
  ARGO_GROUP,
  ARGO_VERSION,
  ARGO_PLURAL,
  FLUX_GROUP,
  FLUX_VERSION,
  FLUX_PLURAL,
};
