'use strict';

const k8s = require('@kubernetes/client-node');
const yaml = require('js-yaml');

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
      // Fall through to empty config for unit tests / local without cluster
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

async function listArgoApplications(custom) {
  const res = await custom.listClusterCustomObject({
    group: ARGO_GROUP,
    version: ARGO_VERSION,
    plural: ARGO_PLURAL,
  });
  // client-node v1 returns the body directly; older shapes use .body
  const body = res && res.items !== undefined ? res : res.body;
  return body.items || [];
}

async function listFluxKustomizations(custom) {
  const res = await custom.listClusterCustomObject({
    group: FLUX_GROUP,
    version: FLUX_VERSION,
    plural: FLUX_PLURAL,
  });
  const body = res && res.items !== undefined ? res : res.body;
  return { items: body.items || [] };
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
