#!/usr/bin/env bash
# Measure GitOps Time-to-Ready / Self-Heal / Rollback.
# Progress logs go to stderr; the final CSV line goes to stdout.
# Exits non-zero if any measurement fails (no failure masking).
set -euo pipefail

NAMESPACE=${1:-argocd-demo}
APP_NAME=${2:-nginx-app}
GITOPS_TOOL=${3:-argocd}
TIMEOUT=${BENCHMARK_TIMEOUT:-300}

log() { printf '%s\n' "$*" >&2; }
fail() { log "ERROR: $*"; echo "failed" >&2; return 1; }

log "=== GitOps Performance Benchmark: ${GITOPS_TOOL} ==="
log "Namespace: ${NAMESPACE}"
log "Application: ${APP_NAME}"
log "Timeout: ${TIMEOUT}s"
log ""

require_deployment() {
  if ! kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    fail "deployment/${APP_NAME} not found in namespace ${NAMESPACE}"
    return 1
  fi
}

wait_deployment_available() {
  local start_time=$1
  local elapsed=0
  while [ "${elapsed}" -lt "${TIMEOUT}" ]; do
    if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      local desired ready
      desired=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
      ready=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      desired=${desired:-0}
      ready=${ready:-0}
      if [ "${desired}" != "0" ] && [ "${ready}" = "${desired}" ]; then
        local end_time
        end_time=$(date +%s)
        echo $((end_time - start_time))
        return 0
      fi
    fi
    sleep 2
    elapsed=$(($(date +%s) - start_time))
  done
  fail "deployment/${APP_NAME} not Available within ${TIMEOUT}s"
  return 1
}

measure_time_to_ready() {
  local start_time
  start_time=$(date +%s)
  local elapsed=0

  log "Measuring time to first Ready/Synced state..."

  if [ "${GITOPS_TOOL}" = "argocd" ]; then
    while [ "${elapsed}" -lt "${TIMEOUT}" ]; do
      local sync health
      sync=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
      health=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)
      if [ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ]; then
        # Also require the workload itself to be ready
        if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
          local desired ready
          desired=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
          ready=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
          if [ "${desired}" != "0" ] && [ "${ready}" = "${desired}" ]; then
            local end_time
            end_time=$(date +%s)
            echo $((end_time - start_time))
            return 0
          fi
        fi
      fi
      sleep 2
      elapsed=$(($(date +%s) - start_time))
    done
    local sync_final health_final msg_final
    sync_final=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "missing")
    health_final=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "missing")
    msg_final=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.conditions[-1].message}' 2>/dev/null || true)
    kubectl get application "${APP_NAME}" -n argocd -o yaml >&2 || true
    fail "Argo CD app not Synced/Healthy within ${TIMEOUT}s (sync=${sync_final} health=${health_final} msg=${msg_final})"
    return 1
  fi

  # Flux: wait for Kustomization Ready, then deployment Available
  while [ "${elapsed}" -lt "${TIMEOUT}" ]; do
    local ready_status
    ready_status=$(kubectl get kustomization flux-nginx-app -n flux-system \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "${ready_status}" = "True" ]; then
      if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        local desired ready
        desired=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        ready=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "${desired}" != "0" ] && [ "${ready}" = "${desired}" ]; then
          local end_time
          end_time=$(date +%s)
          echo $((end_time - start_time))
          return 0
        fi
      fi
    fi
    sleep 2
    elapsed=$(($(date +%s) - start_time))
  done
  kubectl get kustomization flux-nginx-app -n flux-system -o yaml >&2 || true
  kubectl get gitrepository local-repo -n flux-system -o yaml >&2 || true
  fail "Flux kustomization/deployment not Ready within ${TIMEOUT}s"
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
  # Brief pause so the drift is observable before controllers reconcile
  sleep 3

  local start_time elapsed=0
  start_time=$(date +%s)

  while [ "${elapsed}" -lt "${TIMEOUT}" ]; do
    local current_replicas ready_replicas
    current_replicas=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    ready_replicas=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    current_replicas=${current_replicas:-0}
    ready_replicas=${ready_replicas:-0}

    if [ "${current_replicas}" = "${original_replicas}" ] && [ "${ready_replicas}" = "${original_replicas}" ]; then
      local end_time
      end_time=$(date +%s)
      echo $((end_time - start_time))
      return 0
    fi

    sleep 2
    elapsed=$(($(date +%s) - start_time))
  done

  fail "self-heal did not restore replicas=${original_replicas} within ${TIMEOUT}s"
  return 1
}

measure_rollback() {
  log "Measuring rollback time after deployment deletion..."
  require_deployment

  kubectl delete deployment "${APP_NAME}" -n "${NAMESPACE}" --wait=true --timeout=60s >/dev/null

  local start_time elapsed=0
  start_time=$(date +%s)

  while [ "${elapsed}" -lt "${TIMEOUT}" ]; do
    if kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      local desired ready
      desired=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
      ready=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      desired=${desired:-0}
      ready=${ready:-0}
      if [ "${desired}" != "0" ] && [ "${ready}" = "${desired}" ]; then
        local end_time
        end_time=$(date +%s)
        echo $((end_time - start_time))
        return 0
      fi
    fi

    sleep 2
    elapsed=$(($(date +%s) - start_time))
  done

  fail "rollback did not recreate deployment/${APP_NAME} within ${TIMEOUT}s"
  return 1
}

# Validate numeric result
assert_numeric() {
  local label=$1 value=$2
  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    fail "${label} produced non-numeric result: '${value}'"
    return 1
  fi
}

time_to_ready=$(measure_time_to_ready)
assert_numeric "time_to_ready" "${time_to_ready}"

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
