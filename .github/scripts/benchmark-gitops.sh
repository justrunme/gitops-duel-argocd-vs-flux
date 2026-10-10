#!/usr/bin/env bash
# Measure GitOps Time-to-Ready / Self-Heal / Rollback.
# Progress logs go to stderr; the final CSV line goes to stdout.
# Exits non-zero if any measurement fails (no failure masking).
set -euo pipefail

NAMESPACE=${1:-argocd-demo}
APP_NAME=${2:-nginx-app}
GITOPS_TOOL=${3:-argocd}
TIMEOUT=${BENCHMARK_TIMEOUT:-300}
REPO_URL=${TF_VAR_git_repository_url:-https://github.com/justrunme/gitops-duel-argocd-vs-flux.git}
GIT_BRANCH=${TF_VAR_git_branch:-main}
POLL_INTERVAL=${BENCHMARK_POLL_INTERVAL:-0.5}

log() { printf '%s\n' "$*" >&2; }
fail() { log "ERROR: $*"; return 1; }

now() { date +%s.%N; }

# Elapsed seconds between start and now, 3 decimal places
elapsed_since() {
  local start=$1
  awk -v s="${start}" -v e="$(now)" 'BEGIN { printf "%.3f", e - s }'
}

elapsed_int() {
  local start=$1
  awk -v s="${start}" -v e="$(now)" 'BEGIN { printf "%d", e - s }'
}

# Accept integers or decimals; reject empty / non-numeric / masked strings
assert_numeric() {
  local label=$1 value=$2
  if ! [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    fail "${label} produced non-numeric result: '${value}'"
    return 1
  fi
}

# Time-to-Ready must be a real cold-start measurement (> 0)
assert_ready_credible() {
  local value=$1
  assert_numeric "time_to_ready" "${value}"
  awk -v v="${value}" 'BEGIN { exit (v > 0 ? 0 : 1) }' \
    || fail "time_to_ready=${value}s is not credible (timer likely started after the workload was already ready)"
}

deployment_available() {
  kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1 || return 1
  local desired ready
  desired=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  ready=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  desired=${desired:-0}
  ready=${ready:-0}
  [ "${desired}" != "0" ] && [ "${ready}" = "${desired}" ]
}

ensure_namespace() {
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

# Remove workload objects so the next sync is a cold create
wipe_workload() {
  kubectl delete deployment "${APP_NAME}" -n "${NAMESPACE}" --ignore-not-found --wait=true --timeout=90s >/dev/null 2>&1 || true
  kubectl delete service "${APP_NAME}" -n "${NAMESPACE}" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
  local deadline=$(( $(date +%s) + 60 ))
  while kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      fail "deployment/${APP_NAME} still present in ${NAMESPACE} after wipe"
      return 1
    fi
    sleep 0.5
  done
}

require_deployment() {
  if ! kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    fail "deployment/${APP_NAME} not found in namespace ${NAMESPACE}"
    return 1
  fi
}

log "=== GitOps Performance Benchmark: ${GITOPS_TOOL} ==="
log "Namespace: ${NAMESPACE}"
log "Application: ${APP_NAME}"
log "Repo: ${REPO_URL} @ ${GIT_BRANCH}"
log "Timeout: ${TIMEOUT}s"
log ""

create_argocd_application() {
  cat <<YAML | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${GIT_BRANCH}
    path: apps/argocd/nginx
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
YAML
}

create_flux_kustomization() {
  cat <<YAML | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-nginx-app
  namespace: flux-system
spec:
  interval: 10s
  timeout: 60s
  retryInterval: 10s
  path: ./apps/flux/nginx
  prune: true
  wait: true
  targetNamespace: ${NAMESPACE}
  sourceRef:
    kind: GitRepository
    name: local-repo
YAML
}

measure_time_to_ready() {
  log "Measuring time to Ready from Application/Kustomization creation (cold start)..."

  ensure_namespace

  if [ "${GITOPS_TOOL}" = "argocd" ]; then
    # Prefer live values from an existing Application when present
    if kubectl get application "${APP_NAME}" -n argocd >/dev/null 2>&1; then
      REPO_URL=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.spec.source.repoURL}')
      GIT_BRANCH=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.spec.source.targetRevision}')
      log "Using existing Application source: ${REPO_URL} @ ${GIT_BRANCH}"
    fi

    # Tear down Application (prune) and wipe any leftover workload
    kubectl delete application "${APP_NAME}" -n argocd --ignore-not-found --wait=true --timeout=120s >/dev/null
    wipe_workload

    if kubectl get application "${APP_NAME}" -n argocd >/dev/null 2>&1; then
      fail "Argo CD Application ${APP_NAME} still exists after delete"
      return 1
    fi
    if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      fail "deployment/${APP_NAME} still exists in ${NAMESPACE} before cold start"
      return 1
    fi

    local start_time
    start_time=$(now)
    create_argocd_application >/dev/null

    while [ "$(elapsed_int "${start_time}")" -lt "${TIMEOUT}" ]; do
      local sync health
      sync=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
      health=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)
      if [ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ] && deployment_available; then
        elapsed_since "${start_time}"
        return 0
      fi
      sleep "${POLL_INTERVAL}"
    done

    kubectl get application "${APP_NAME}" -n argocd -o yaml >&2 || true
    kubectl get deploy,svc,pods -n "${NAMESPACE}" >&2 || true
    fail "Argo CD cold-start not Synced/Healthy+Available within ${TIMEOUT}s"
    return 1
  fi

  # Flux path
  if kubectl get kustomization flux-nginx-app -n flux-system >/dev/null 2>&1; then
    log "Recreating Flux Kustomization flux-nginx-app (GitRepository kept)"
  fi
  if ! kubectl get gitrepository local-repo -n flux-system >/dev/null 2>&1; then
    fail "Flux GitRepository local-repo not found in flux-system (required for cold start)"
    return 1
  fi

  kubectl delete kustomization flux-nginx-app -n flux-system --ignore-not-found --wait=true --timeout=120s >/dev/null
  wipe_workload

  if kubectl get kustomization flux-nginx-app -n flux-system >/dev/null 2>&1; then
    fail "Flux Kustomization flux-nginx-app still exists after delete"
    return 1
  fi
  if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    fail "deployment/${APP_NAME} still exists in ${NAMESPACE} before cold start"
    return 1
  fi

  local start_time
  start_time=$(now)
  create_flux_kustomization >/dev/null

  while [ "$(elapsed_int "${start_time}")" -lt "${TIMEOUT}" ]; do
    local ready_status
    ready_status=$(kubectl get kustomization flux-nginx-app -n flux-system \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "${ready_status}" = "True" ] && deployment_available; then
      elapsed_since "${start_time}"
      return 0
    fi
    sleep "${POLL_INTERVAL}"
  done

  kubectl get kustomization flux-nginx-app -n flux-system -o yaml >&2 || true
  kubectl get gitrepository local-repo -n flux-system -o yaml >&2 || true
  kubectl get deploy,svc,pods -n "${NAMESPACE}" >&2 || true
  fail "Flux cold-start Kustomization/deployment not Ready within ${TIMEOUT}s"
  return 1
}

measure_self_heal() {
  log "Measuring self-heal time after manual drift..."
  require_deployment

  local original_replicas
  original_replicas=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
  if [ -z "${original_replicas}" ] || [ "${original_replicas}" = "0" ]; then
    fail "deployment/${APP_NAME} has invalid replica count '${original_replicas}'"
    return 1
  fi

  kubectl scale deployment "${APP_NAME}" --replicas=0 -n "${NAMESPACE}" >/dev/null
  # Wait until drift is visible (replicas scaled down) before starting the timer
  local drift_deadline=$(( $(date +%s) + 30 ))
  while true; do
    local cur
    cur=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [ "${cur}" = "0" ]; then
      break
    fi
    if [ "$(date +%s)" -ge "${drift_deadline}" ]; then
      fail "failed to observe replica drift to 0 before self-heal timing"
      return 1
    fi
    sleep 0.2
  done

  local start_time
  start_time=$(now)

  while [ "$(elapsed_int "${start_time}")" -lt "${TIMEOUT}" ]; do
    local current_replicas ready_replicas
    current_replicas=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    ready_replicas=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    current_replicas=${current_replicas:-0}
    ready_replicas=${ready_replicas:-0}

    if [ "${current_replicas}" = "${original_replicas}" ] && [ "${ready_replicas}" = "${original_replicas}" ]; then
      elapsed_since "${start_time}"
      return 0
    fi
    sleep "${POLL_INTERVAL}"
  done

  fail "self-heal did not restore replicas=${original_replicas} within ${TIMEOUT}s"
  return 1
}

measure_rollback() {
  log "Measuring rollback time after deployment deletion..."
  require_deployment

  kubectl delete deployment "${APP_NAME}" -n "${NAMESPACE}" --wait=true --timeout=90s >/dev/null

  if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    fail "deployment/${APP_NAME} still present immediately after delete"
    return 1
  fi

  local start_time
  start_time=$(now)

  while [ "$(elapsed_int "${start_time}")" -lt "${TIMEOUT}" ]; do
    if deployment_available; then
      elapsed_since "${start_time}"
      return 0
    fi
    sleep "${POLL_INTERVAL}"
  done

  fail "rollback did not recreate deployment/${APP_NAME} within ${TIMEOUT}s"
  return 1
}

time_to_ready=$(measure_time_to_ready)
assert_ready_credible "${time_to_ready}"

time_to_heal=$(measure_self_heal)
assert_numeric "time_to_heal" "${time_to_heal}"

time_to_rollback=$(measure_rollback)
assert_numeric "time_to_rollback" "${time_to_rollback}"

log ""
log "Results:"
log "  Time to Ready: ${time_to_ready}s"
log "  Time to Self-Heal: ${time_to_heal}s"
log "  Time to Rollback: ${time_to_rollback}s"
log ""

# Sole stdout line — consumed by callers
echo "${time_to_ready},${time_to_heal},${time_to_rollback}"
