#!/usr/bin/env bash
# Run N benchmark samples for each tool × profile and write docs/results.md.
# Exits non-zero if any sample fails (no failure masking).
set -euo pipefail

mkdir -p docs
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ARGO_NS=${ARGO_TARGET_NAMESPACE:-argocd-demo}
FLUX_NS=${FLUX_TARGET_NAMESPACE:-flux-demo}
SAMPLES=${BENCHMARK_SAMPLES:-3}
PROFILES=${BENCHMARK_PROFILES:-equal-10s,defaults}
# defaults profile can need longer waits (Argo 180s reconciliation)
DEFAULTS_TIMEOUT=${BENCHMARK_DEFAULTS_TIMEOUT:-420}

is_positive_number() {
  local v=$1
  [[ "${v}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v x="${v}" 'BEGIN { exit (x > 0 ? 0 : 1) }'
}

is_number() {
  local v=$1
  [[ "${v}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

fmt_cell() {
  # median (min–max) from JSON summary object on stdin keys via python
  local json=$1 key=$2
  python3 - "$json" "$key" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
k = sys.argv[2]
m = data[k]
print(f"{m['median']} (min {m['min']}, max {m['max']}, n={m['n']})")
PY
}

run_tool_samples() {
  local tool=$1
  local ns=$2
  local profile=$3
  local timeout=$4
  local samples_file=$5

  : >"${samples_file}"
  local i
  for i in $(seq 1 "${SAMPLES}"); do
    echo "=== ${tool} profile=${profile} sample ${i}/${SAMPLES} ===" >&2
    local line
    line=$(
      BENCHMARK_PROFILE="${profile}" BENCHMARK_TIMEOUT="${timeout}" \
        "${SCRIPT_DIR}/benchmark-gitops.sh" "${ns}" nginx-app "${tool}"
    )
    printf '%s\n' "${line}" >>"${samples_file}"
    IFS=',' read -r ready heal del commit <<<"${line}"
    is_positive_number "${ready}" || { echo "${tool} time_to_ready invalid: ${line}" >&2; exit 1; }
    is_number "${heal}" || { echo "${tool} time_to_heal invalid: ${line}" >&2; exit 1; }
    is_number "${del}" || { echo "${tool} time_to_deletion_recovery invalid: ${line}" >&2; exit 1; }
    is_positive_number "${commit}" || { echo "${tool} time_to_commit_ready invalid: ${line}" >&2; exit 1; }
  done
}

TMPDIR_BENCH=$(mktemp -d)
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bench-local-git.sh"
cleanup_all() {
  # Only local temp files here. Remote ci/bench-* cleanup must wait until after
  # Simulate ArgoCD/Flux steps (workflow "Cleanup temporary bench branches").
  rm -rf "${TMPDIR_BENCH}"
}
trap cleanup_all EXIT

{
  echo "# GitOps Performance Benchmarks"
  echo ""
  echo "Automated performance comparison between Argo CD and Flux."
  echo ""
  echo "Samples per metric: **${SAMPLES}** (reported as median with min/max)."
  echo ""
  echo "Profiles:"
  echo ""
  echo "| Profile | Argo CD \`timeout.reconciliation\` | Flux GitRepository/Kustomization \`interval\` |"
  echo "|---------|-----------------------------------|-----------------------------------------------|"
  echo "| \`equal-10s\` | 10s | 10s |"
  echo "| \`defaults\` | 180s (Argo stock) | 1m (CI-bounded stand-in; stock Flux Kustomization default is 10m) |"
  echo ""
  echo "Commit→ready pushes an image-tag change to a temporary \`ci/bench-<run-id>\` GitHub branch and times convergence (polling only; no webhooks). The branch is deleted in an \`if: always()\` cleanup step."
  echo ""
  echo "Deletion recovery recreates a deleted Deployment (not a Git revert)."
  echo ""
} > docs/results.md

IFS=',' read -r -a PROFILE_ARR <<<"${PROFILES}"

for profile in "${PROFILE_ARR[@]}"; do
  profile=$(echo "${profile}" | xargs)
  [ -n "${profile}" ] || continue
  timeout=${BENCHMARK_TIMEOUT:-300}
  if [ "${profile}" = "defaults" ]; then
    timeout=${DEFAULTS_TIMEOUT}
  fi

  echo "Running profile=${profile} (timeout=${timeout}s, N=${SAMPLES})..." >&2

  apply_profile() {
    local p=$1
    local recon flux_interval branch url
    case "${p}" in
      equal-10s) recon=10s; flux_interval=10s ;;
      defaults) recon=180s; flux_interval=1m ;;
      *) echo "unknown profile ${p}" >&2; return 1 ;;
    esac
    echo "Applying profile ${p}: Argo reconciliation=${recon}, Flux interval=${flux_interval}" >&2
    kubectl -n argocd patch configmap argocd-cm --type merge \
      -p "{\"data\":{\"timeout.reconciliation\":\"${recon}\"}}" >/dev/null
    if kubectl -n argocd get statefulset argocd-application-controller >/dev/null 2>&1; then
      kubectl -n argocd rollout restart statefulset/argocd-application-controller >/dev/null
      kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=180s >/dev/null
    elif kubectl -n argocd get deployment argocd-application-controller >/dev/null 2>&1; then
      kubectl -n argocd rollout restart deployment/argocd-application-controller >/dev/null
      kubectl -n argocd rollout status deployment/argocd-application-controller --timeout=180s >/dev/null
    else
      echo "argocd-application-controller (statefulset/deployment) not found" >&2
      return 1
    fi
    if kubectl get gitrepository local-repo -n flux-system >/dev/null 2>&1; then
      url=$(kubectl get gitrepository local-repo -n flux-system -o jsonpath='{.spec.url}')
      branch=$(kubectl get gitrepository local-repo -n flux-system -o jsonpath='{.spec.ref.branch}')
      cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: local-repo
  namespace: flux-system
spec:
  interval: ${flux_interval}
  timeout: 60s
  url: ${url}
  ref:
    branch: ${branch}
YAML
      cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-nginx-app
  namespace: flux-system
spec:
  interval: ${flux_interval}
  timeout: 60s
  retryInterval: ${flux_interval}
  path: ./apps/flux/nginx
  prune: true
  wait: true
  targetNamespace: ${FLUX_NS}
  sourceRef:
    kind: GitRepository
    name: local-repo
YAML
    fi
  }
  apply_profile "${profile}"

  argo_file="${TMPDIR_BENCH}/argo-${profile}.csv"
  flux_file="${TMPDIR_BENCH}/flux-${profile}.csv"

  run_tool_samples argocd "${ARGO_NS}" "${profile}" "${timeout}" "${argo_file}"
  run_tool_samples flux "${FLUX_NS}" "${profile}" "${timeout}" "${flux_file}"

  argo_json=$(python3 "${SCRIPT_DIR}/bench-stats.py" <"${argo_file}")
  flux_json=$(python3 "${SCRIPT_DIR}/bench-stats.py" <"${flux_file}")

  {
    echo "## Profile \`${profile}\`"
    echo ""
    echo "| Tool | Time to Ready (s) | Time to Self-Heal (s) | Time to Deletion Recovery (s) | Time to Commit→Ready (s) |"
    echo "|------|-------------------|----------------------|-------------------------------|--------------------------|"
    echo "| Argo CD | $(fmt_cell "${argo_json}" time_to_ready_seconds) | $(fmt_cell "${argo_json}" time_to_self_heal_seconds) | $(fmt_cell "${argo_json}" time_to_deletion_recovery_seconds) | $(fmt_cell "${argo_json}" time_to_commit_ready_seconds) |"
    echo "| Flux | $(fmt_cell "${flux_json}" time_to_ready_seconds) | $(fmt_cell "${flux_json}" time_to_self_heal_seconds) | $(fmt_cell "${flux_json}" time_to_deletion_recovery_seconds) | $(fmt_cell "${flux_json}" time_to_commit_ready_seconds) |"
    echo ""
  } >> docs/results.md

  # Persist per-profile raw samples for write_demo_results.py
  mkdir -p docs/bench-raw
  cp "${argo_file}" "docs/bench-raw/${profile}-argocd.csv"
  cp "${flux_file}" "docs/bench-raw/${profile}-flux.csv"
  printf '%s\n' "${argo_json}" >"docs/bench-raw/${profile}-argocd.json"
  printf '%s\n' "${flux_json}" >"docs/bench-raw/${profile}-flux.json"
done


# Leave controllers on the CI-tracked branch so post-benchmark Simulate steps
# can self-heal without depending on the temporary ci/bench-* ref.
restore_ci_sources() {
  local cold_repo="${TF_VAR_git_repository_url:-https://github.com/justrunme/gitops-duel-argocd-vs-flux.git}"
  local cold_rev="${TF_VAR_git_branch:-${GITHUB_REF_NAME:-main}}"
  echo "Restoring controllers to ${cold_repo} @ ${cold_rev}" >&2
  if kubectl get application nginx-app -n argocd >/dev/null 2>&1; then
    cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${cold_repo}
    targetRevision: ${cold_rev}
    path: apps/argocd/nginx
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGO_NS}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
YAML
  fi
  if kubectl get gitrepository local-repo -n flux-system >/dev/null 2>&1; then
    cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: local-repo
  namespace: flux-system
spec:
  interval: 10s
  timeout: 60s
  url: ${cold_repo}
  ref:
    branch: ${cold_rev}
YAML
  fi
  # Give controllers a moment to reconcile desired state before Simulate steps
  sleep 5
  kubectl wait --for=condition=available deployment/nginx-app -n "${ARGO_NS}" --timeout=180s >/dev/null 2>&1 || true
  kubectl wait --for=condition=available deployment/nginx-app -n "${FLUX_NS}" --timeout=180s >/dev/null 2>&1 || true
}
restore_ci_sources

{
  echo "Run date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "Source run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-local}"
  echo ""
  echo "These values are taken verbatim from the CI job. No estimated timings are published."
} >> docs/results.md

cat docs/results.md
