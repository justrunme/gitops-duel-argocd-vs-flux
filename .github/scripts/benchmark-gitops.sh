#!/usr/bin/env bash
# Measure GitOps Time-to-Ready / Self-Heal / Deletion-Recovery / Commit-to-Ready.
# Progress logs go to stderr; the final CSV line goes to stdout:
#   ready,heal,deletion_recovery,commit_ready
# Exits non-zero if any measurement fails (no failure masking).
set -euo pipefail

NAMESPACE=${1:-argocd-demo}
APP_NAME=${2:-nginx-app}
GITOPS_TOOL=${3:-argocd}
TIMEOUT=${BENCHMARK_TIMEOUT:-300}
REPO_URL=${TF_VAR_git_repository_url:-https://github.com/justrunme/gitops-duel-argocd-vs-flux.git}
GIT_BRANCH=${TF_VAR_git_branch:-main}
POLL_INTERVAL=${BENCHMARK_POLL_INTERVAL:-0.5}
# equal-10s | defaults
BENCHMARK_PROFILE=${BENCHMARK_PROFILE:-equal-10s}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bench-local-git.sh"

log() { printf '%s\n' "$*" >&2; }
fail() { log "ERROR: $*"; return 1; }

now() { date +%s.%N; }

elapsed_since() {
  local start=$1
  awk -v s="${start}" -v e="$(now)" 'BEGIN { printf "%.3f", e - s }'
}

elapsed_int() {
  local start=$1
  awk -v s="${start}" -v e="$(now)" 'BEGIN { printf "%d", e - s }'
}

assert_numeric() {
  local label=$1 value=$2
  if ! [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    fail "${label} produced non-numeric result: '${value}'"
    return 1
  fi
}

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

deployment_image() {
  kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}

ensure_namespace() {
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

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

profile_flux_interval() {
  case "${BENCHMARK_PROFILE}" in
    equal-10s) echo "10s" ;;
    defaults) echo "1m" ;; # Flux Kustomization stock default is 10m; 1m keeps CI bounded while remaining slower than tuned
    *) fail "unknown BENCHMARK_PROFILE=${BENCHMARK_PROFILE}"; return 1 ;;
  esac
}

profile_argocd_reconciliation() {
  case "${BENCHMARK_PROFILE}" in
    equal-10s) echo "10s" ;;
    defaults) echo "180s" ;;
    *) fail "unknown BENCHMARK_PROFILE=${BENCHMARK_PROFILE}"; return 1 ;;
  esac
}

apply_argocd_reconciliation() {
  local recon
  recon=$(profile_argocd_reconciliation)
  log "Setting Argo CD timeout.reconciliation=${recon} (profile=${BENCHMARK_PROFILE})"
  kubectl -n argocd create configmap argocd-cm --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n argocd patch configmap argocd-cm --type merge \
    -p "{\"data\":{\"timeout.reconciliation\":\"${recon}\"}}" >/dev/null
  # Restart application controller so the setting is picked up (must succeed)
  if kubectl -n argocd get statefulset argocd-application-controller >/dev/null 2>&1; then
    kubectl -n argocd rollout restart statefulset/argocd-application-controller >/dev/null
    kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=180s >/dev/null
  elif kubectl -n argocd get deployment argocd-application-controller >/dev/null 2>&1; then
    kubectl -n argocd rollout restart deployment/argocd-application-controller >/dev/null
    kubectl -n argocd rollout status deployment/argocd-application-controller --timeout=180s >/dev/null
  else
    fail "argocd-application-controller (statefulset/deployment) not found"
  fi
}

ensure_argocd_http_repo() {
  local url=$1
  kubectl -n argocd delete secret repo-bench-git --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n argocd create secret generic repo-bench-git \
    --from-literal=type=git \
    --from-literal=url="${url}" \
    --from-literal=insecure=true >/dev/null
  kubectl -n argocd label secret repo-bench-git \
    argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
}

create_argocd_application() {
  local repo=${1:-${REPO_URL}}
  local rev=${2:-${GIT_BRANCH}}
  cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${repo}
    targetRevision: ${rev}
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
  local interval
  interval=$(profile_flux_interval)
  cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-nginx-app
  namespace: flux-system
spec:
  interval: ${interval}
  timeout: 60s
  retryInterval: ${interval}
  path: ./apps/flux/nginx
  prune: true
  wait: true
  targetNamespace: ${NAMESPACE}
  sourceRef:
    kind: GitRepository
    name: local-repo
YAML
}

enable_flux_http() {
  # Flux source-controller disables plain HTTP unless explicitly allowed.
  local deploy=source-controller
  if ! kubectl -n flux-system get deploy "${deploy}" >/dev/null 2>&1; then
    return 0
  fi
  local args
  args=$(kubectl -n flux-system get deploy "${deploy}" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || true)
  if echo "${args}" | grep -q -- '--insecure-allow-http'; then
    return 0
  fi
  log "Enabling --insecure-allow-http on flux-system/${deploy}"
  kubectl -n flux-system patch deploy "${deploy}" --type='json' -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure-allow-http"}
  ]' >/dev/null
  kubectl -n flux-system rollout status deploy/"${deploy}" --timeout=180s >/dev/null
}

patch_flux_gitrepository() {
  local url=$1
  local interval
  interval=$(profile_flux_interval)
  if [[ "${url}" == http://* ]]; then
    enable_flux_http
  fi
  cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: local-repo
  namespace: flux-system
spec:
  interval: ${interval}
  timeout: 60s
  url: ${url}
  ref:
    branch: main
YAML
}

log "=== GitOps Performance Benchmark: ${GITOPS_TOOL} ==="
log "Namespace: ${NAMESPACE}"
log "Application: ${APP_NAME}"
log "Profile: ${BENCHMARK_PROFILE}"
log "Repo: ${REPO_URL} @ ${GIT_BRANCH}"
log "Timeout: ${TIMEOUT}s"
log "Intervals: Argo reconciliation=$(profile_argocd_reconciliation), Flux interval=$(profile_flux_interval)"
log ""

# Profile controllers are applied by run-benchmark-demo.sh once per profile
# (set BENCHMARK_APPLY_PROFILE=1 to apply inline for standalone runs).
if [ "${BENCHMARK_APPLY_PROFILE:-0}" = "1" ]; then
  apply_argocd_reconciliation
fi

measure_time_to_ready() {
  log "Measuring time to Ready from Application/Kustomization creation (cold start)..."

  ensure_namespace

  if [ "${GITOPS_TOOL}" = "argocd" ]; then
    # Always cold-start from the CI-tracked GitHub repo/branch (not the local bench git URL).
    local cold_repo="${TF_VAR_git_repository_url:-${REPO_URL}}"
    local cold_rev="${TF_VAR_git_branch:-${GIT_BRANCH}}"
    log "Cold-start source: ${cold_repo} @ ${cold_rev}"

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
    create_argocd_application "${cold_repo}" "${cold_rev}" >/dev/null

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

  # Flux path — recreate BOTH GitRepository artifact path fairness: keep GitRepository
  # but recreate Kustomization. For cold-start we keep GitRepository (artifact cached)
  # matching prior behaviour; commit-to-ready exercises a fresh fetch.
  if ! kubectl get gitrepository local-repo -n flux-system >/dev/null 2>&1; then
    fail "Flux GitRepository local-repo not found in flux-system (required for cold start)"
    return 1
  fi
  # Restore Flux GitRepository to the CI-tracked remote for cold-start fairness
  local cold_repo="${TF_VAR_git_repository_url:-${REPO_URL}}"
  local cold_rev="${TF_VAR_git_branch:-${GIT_BRANCH}}"
  cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: local-repo
  namespace: flux-system
spec:
  interval: $(profile_flux_interval)
  timeout: 60s
  url: ${cold_repo}
  ref:
    branch: ${cold_rev}
YAML

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
  log "Measuring self-heal time after manual replica drift..."
  require_deployment

  local original_replicas
  original_replicas=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
  if [ -z "${original_replicas}" ] || [ "${original_replicas}" = "0" ]; then
    fail "deployment/${APP_NAME} has invalid replica count '${original_replicas}'"
    return 1
  fi

  kubectl scale deployment "${APP_NAME}" --replicas=0 -n "${NAMESPACE}" >/dev/null
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

# Deletion recovery (formerly labeled "rollback"): recreate after out-of-band delete
measure_deletion_recovery() {
  log "Measuring deletion-recovery time after deployment deletion..."
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

  fail "deletion recovery did not recreate deployment/${APP_NAME} within ${TIMEOUT}s"
  return 1
}

measure_commit_to_ready() {
  log "Measuring commit→ready (image tag bump on temporary GitHub branch)..."
  require_deployment

  if [ -z "${BENCH_GIT_BRANCH:-}" ] || [ ! -d "${BENCH_GIT_SRC:-/nonexistent}/.git" ]; then
    setup_bench_git_server "$(cd "${SCRIPT_DIR}/../.." && pwd)"
  fi

  local manifest_file baseline_image target_image
  if [ "${GITOPS_TOOL}" = "argocd" ]; then
    manifest_file="${BENCH_GIT_SRC}/apps/argocd/nginx/deployment.yaml"
  else
    manifest_file="${BENCH_GIT_SRC}/apps/flux/nginx/deployment.yaml"
  fi
  baseline_image=$(grep -E '^[[:space:]]*image:' "${manifest_file}" | head -n1 | awk '{print $2}')
  if [ -z "${baseline_image}" ]; then
    fail "could not read baseline image from ${manifest_file}"
    return 1
  fi
  # Flip relative to the git working copy (not the live cluster) so N>1 samples always commit.
  if [ "${baseline_image}" = "nginx:1.27-alpine" ]; then
    target_image=nginx:1.26-alpine
  else
    target_image=nginx:1.27-alpine
  fi
  log "commit→ready baseline=${baseline_image} target=${target_image}"

  # Ensure the temporary branch exists on the remote before controllers poll it.
  # (Cold-start may have pointed Flux/Argo away from it; never leave a dangling ref.)
  ensure_bench_branch_pushed

  # Retarget to the temporary HTTPS GitHub branch
  if [ "${GITOPS_TOOL}" = "argocd" ]; then
    create_argocd_application "${BENCH_GIT_URL}" "${BENCH_GIT_BRANCH}" >/dev/null
  else
    local interval
    interval=$(profile_flux_interval)
    # Recreate the GitRepository so status/artifact cannot stick to the CI branch.
    kubectl -n flux-system delete gitrepository local-repo --ignore-not-found --wait=true --timeout=60s >/dev/null
    cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: local-repo
  namespace: flux-system
spec:
  interval: ${interval}
  timeout: 60s
  url: ${BENCH_GIT_URL}
  ref:
    branch: ${BENCH_GIT_BRANCH}
YAML
    create_flux_kustomization >/dev/null
  fi

  # Warm to the current git baseline before committing the flip
  local warm_deadline=$(( $(date +%s) + TIMEOUT ))
  while true; do
    if [ "$(deployment_image)" = "${baseline_image}" ] && deployment_available; then
      if [ "${GITOPS_TOOL}" = "argocd" ]; then
        local sync health
        sync=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
        health=$(kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)
        if [ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ]; then
          break
        fi
      else
        local ready_status
        ready_status=$(kubectl get kustomization flux-nginx-app -n flux-system \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
        if [ "${ready_status}" = "True" ]; then
          break
        fi
      fi
    fi
    if [ "$(date +%s)" -ge "${warm_deadline}" ]; then
      log "warm state: image=$(deployment_image) want=${baseline_image}"
      if [ "${GITOPS_TOOL}" = "argocd" ]; then
        kubectl get application "${APP_NAME}" -n argocd -o yaml >&2 || true
      else
        kubectl get gitrepository local-repo -n flux-system -o yaml >&2 || true
        kubectl get kustomization flux-nginx-app -n flux-system -o yaml >&2 || true
      fi
      fail "did not reach baseline image ${baseline_image} on bench branch before commit timing"
      return 1
    fi
    sleep "${POLL_INTERVAL}"
  done

  sed -i "s|image: nginx:.*|image: ${target_image}|" "${manifest_file}"
  if git -C "${BENCH_GIT_SRC}" diff --quiet; then
    fail "image flip produced no git diff (baseline=${baseline_image} target=${target_image})"
    return 1
  fi
  bench_git_commit "bench: set image ${target_image}"

  # Start the timer only after the commit is visible on the remote. Controllers
  # discover it via their configured poll/reconcile intervals (no webhook nudge).
  local start_time
  start_time=$(now)
  while [ "$(elapsed_int "${start_time}")" -lt "${TIMEOUT}" ]; do
    local img
    img=$(deployment_image)
    if [ "${img}" = "${target_image}" ] && deployment_available; then
      elapsed_since "${start_time}"
      return 0
    fi
    sleep "${POLL_INTERVAL}"
  done

  log "desired image=${target_image} observed=$(deployment_image)"
  if [ "${GITOPS_TOOL}" = "flux" ]; then
    kubectl get gitrepository local-repo -n flux-system -o yaml >&2 || true
    kubectl get kustomization flux-nginx-app -n flux-system -o yaml >&2 || true
  else
    kubectl get application "${APP_NAME}" -n argocd -o yaml >&2 || true
  fi
  fail "commit→ready did not converge to ${target_image} within ${TIMEOUT}s"
  return 1
}

# Defense in depth: measurement helpers must only print the timing, but if any
# tooling leaks a line to stdout, keep the last line (the elapsed value).
time_to_ready=$(measure_time_to_ready | tail -n 1)
assert_ready_credible "${time_to_ready}"

time_to_heal=$(measure_self_heal | tail -n 1)
assert_numeric "time_to_heal" "${time_to_heal}"

time_to_deletion_recovery=$(measure_deletion_recovery | tail -n 1)
assert_numeric "time_to_deletion_recovery" "${time_to_deletion_recovery}"

time_to_commit_ready=$(measure_commit_to_ready | tail -n 1)
assert_numeric "time_to_commit_ready" "${time_to_commit_ready}"
awk -v v="${time_to_commit_ready}" 'BEGIN { exit (v > 0 ? 0 : 1) }' \
  || fail "time_to_commit_ready=${time_to_commit_ready}s is not credible"

log ""
log "Results (profile=${BENCHMARK_PROFILE}):"
log "  Time to Ready: ${time_to_ready}s"
log "  Time to Self-Heal: ${time_to_heal}s"
log "  Time to Deletion Recovery: ${time_to_deletion_recovery}s"
log "  Time to Commit→Ready: ${time_to_commit_ready}s"
log ""

echo "${time_to_ready},${time_to_heal},${time_to_deletion_recovery},${time_to_commit_ready}"
