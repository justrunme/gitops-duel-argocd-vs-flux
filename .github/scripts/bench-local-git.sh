#!/usr/bin/env bash
# Manage a temporary GitHub branch for commit→ready measurements.
# Branch names are set by the calling workflow (ci/bench-demo-* or ci/bench-duel-*).
# Exports: BENCH_GIT_URL, BENCH_GIT_BRANCH, BENCH_GIT_SRC
set -euo pipefail

BENCH_GIT_SRC=${BENCH_GIT_SRC:-/tmp/gitops-bench-src}
BENCH_GIT_URL=${BENCH_GIT_URL:-${TF_VAR_git_repository_url:-https://github.com/justrunme/gitops-duel-argocd-vs-flux.git}}
BENCH_GIT_BRANCH=${BENCH_GIT_BRANCH:-ci/bench-${GITHUB_RUN_ID:-local-$(date +%s)}-${GITHUB_RUN_ATTEMPT:-1}}

# Commits on the temporary branch use the repo owner identity (branch is deleted after the job).
BENCH_GIT_AUTHOR_NAME=${BENCH_GIT_AUTHOR_NAME:-Andrey Lesnikov}
BENCH_GIT_AUTHOR_EMAIL=${BENCH_GIT_AUTHOR_EMAIL:-52860508+justrunme@users.noreply.github.com}

# Flux / Argo resources retargeted during commit→ready.
BENCH_FLUX_GITREPO=${BENCH_FLUX_GITREPO:-local-repo}
BENCH_FLUX_KUSTOMIZATION=${BENCH_FLUX_KUSTOMIZATION:-flux-nginx-app}
BENCH_ARGO_APP=${BENCH_ARGO_APP:-nginx-app}

log() { printf '%s\n' "$*" >&2; }

require_push_token() {
  if [ -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]; then
    log "ERROR: GITHUB_TOKEN is required to push the temporary bench branch ${BENCH_GIT_BRANCH}"
    return 1
  fi
}

configure_push_remote() {
  local token=${GITHUB_TOKEN:-${GH_TOKEN}}
  local url=$1
  url=${url%.git}.git
  if [[ "${url}" != https://github.com/* ]]; then
    log "ERROR: only https://github.com remotes are supported for bench pushes (got ${url})"
    return 1
  fi
  local path=${url#https://github.com/}
  git -C "${BENCH_GIT_SRC}" remote remove origin >/dev/null 2>&1 || true
  git -C "${BENCH_GIT_SRC}" remote add origin "https://x-access-token:${token}@github.com/${path}"
}

ensure_bench_branch_pushed() {
  require_push_token
  if [ ! -d "${BENCH_GIT_SRC}/.git" ]; then
    log "ERROR: bench git src missing; call setup first"
    return 1
  fi
  # Force-publish current HEAD so Flux/Argo can always resolve the ref.
  git -C "${BENCH_GIT_SRC}" push origin "HEAD:refs/heads/${BENCH_GIT_BRANCH}" --force >/dev/null
  local url=${BENCH_GIT_URL%.git}.git
  local path=${url#https://github.com/}
  local token=${GITHUB_TOKEN:-${GH_TOKEN}}
  if ! git ls-remote "https://x-access-token:${token}@github.com/${path}" "refs/heads/${BENCH_GIT_BRANCH}" | grep -q .; then
    log "ERROR: refs/heads/${BENCH_GIT_BRANCH} not visible after push"
    return 1
  fi
  log "bench-git ref verified: refs/heads/${BENCH_GIT_BRANCH}"
}

# Nudge Flux and Argo after a bench commit so they pick up the new revision promptly.
request_controller_reconcile() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if kubectl get gitrepository "${BENCH_FLUX_GITREPO}" -n flux-system >/dev/null 2>&1; then
    kubectl -n flux-system annotate gitrepository "${BENCH_FLUX_GITREPO}" \
      "reconcile.fluxcd.io/requestedAt=${ts}" --overwrite >/dev/null
  fi
  if kubectl get kustomization "${BENCH_FLUX_KUSTOMIZATION}" -n flux-system >/dev/null 2>&1; then
    kubectl -n flux-system annotate kustomization "${BENCH_FLUX_KUSTOMIZATION}" \
      "reconcile.fluxcd.io/requestedAt=${ts}" --overwrite >/dev/null
  fi

  if kubectl get application "${BENCH_ARGO_APP}" -n argocd >/dev/null 2>&1; then
    # Hard refresh forces a repo fetch of the latest commit on the target revision.
    kubectl -n argocd annotate application "${BENCH_ARGO_APP}" \
      argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  fi
}

bench_git_commit() {
  local message=$1
  require_push_token
  (
    cd "${BENCH_GIT_SRC}"
    git add -A
    if git diff --cached --quiet; then
      log "bench-git: nothing to commit (${message})"
      return 0
    fi
    # Keep git chatter off stdout — callers capture timing via command substitution.
    git \
      -c user.name="${BENCH_GIT_AUTHOR_NAME}" \
      -c user.email="${BENCH_GIT_AUTHOR_EMAIL}" \
      commit -m "${message} [skip ci]" >/dev/null
    git push origin "HEAD:refs/heads/${BENCH_GIT_BRANCH}" >/dev/null
  )
  ensure_bench_branch_pushed
  request_controller_reconcile
}

setup_bench_git_server() {
  local repo_root=${1:-.}
  require_push_token

  rm -rf "${BENCH_GIT_SRC}"
  mkdir -p "${BENCH_GIT_SRC}/apps"
  cp -a "${repo_root}/apps/argocd" "${BENCH_GIT_SRC}/apps/argocd"
  cp -a "${repo_root}/apps/flux" "${BENCH_GIT_SRC}/apps/flux"

  (
    cd "${BENCH_GIT_SRC}"
    git init -b main >/dev/null
    git add -A
    git \
      -c user.name="${BENCH_GIT_AUTHOR_NAME}" \
      -c user.email="${BENCH_GIT_AUTHOR_EMAIL}" \
      commit -m "bench: initial [skip ci]" >/dev/null
  )
  configure_push_remote "${BENCH_GIT_URL}"
  # No -u / no stdout: timing helpers capture stdout via command substitution.
  git -C "${BENCH_GIT_SRC}" push origin "HEAD:refs/heads/${BENCH_GIT_BRANCH}" --force >/dev/null

  export BENCH_GIT_URL BENCH_GIT_BRANCH BENCH_GIT_SRC
  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "BENCH_GIT_BRANCH=${BENCH_GIT_BRANCH}"
      echo "BENCH_GIT_URL=${BENCH_GIT_URL}"
    } >>"${GITHUB_ENV}"
  fi
  log "bench-git ready: ${BENCH_GIT_URL} @ ${BENCH_GIT_BRANCH}"
}

delete_remote_ref() {
  local ref=$1
  # ref like refs/heads/ci/bench-123 or heads/ci/bench-123 or ci/bench-123
  local branch=${ref#refs/heads/}
  branch=${branch#heads/}
  if [ -z "${branch}" ]; then
    return 0
  fi
  if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    log "ERROR: GITHUB_REPOSITORY is required to delete remote ref ${branch}"
    return 1
  fi
  require_push_token
  local token=${GITHUB_TOKEN:-${GH_TOKEN}}

  log "Deleting remote branch ${branch} via API"
  # Encode '/' in branch names (ci/bench-...) so the API path is unambiguous.
  local encoded_branch=${branch//\//%2F}
  local http_code body
  body=$(mktemp)
  http_code=$(curl -sS -o "${body}" -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs/heads/${encoded_branch}")
  case "${http_code}" in
    204|200)
      rm -f "${body}"
      log "Deleted refs/heads/${branch}"
      ;;
    404)
      rm -f "${body}"
      log "refs/heads/${branch} already absent (${http_code})"
      ;;
    422)
      # GitHub git-refs DELETE returns 422 {"message":"Reference does not exist"}
      # when the branch is already gone — same outcome as 404.
      if grep -qi 'Reference does not exist' "${body}" 2>/dev/null; then
        rm -f "${body}"
        log "refs/heads/${branch} already absent (${http_code})"
      else
        log "ERROR: deleting refs/heads/${branch} failed with HTTP ${http_code}"
        cat "${body}" >&2 || true
        rm -f "${body}"
        return 1
      fi
      ;;
    *)
      log "ERROR: deleting refs/heads/${branch} failed with HTTP ${http_code}"
      cat "${body}" >&2 || true
      rm -f "${body}"
      return 1
      ;;
  esac
}

cleanup_bench_git_branch() {
  if [ -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]; then
    log "bench-git cleanup skipped: no GITHUB_TOKEN"
    return 0
  fi

  # Delete only this run's branch — never sweep other ci/bench-* refs.
  if [ -z "${BENCH_GIT_BRANCH:-}" ]; then
    log "ERROR: BENCH_GIT_BRANCH is required for cleanup"
    return 1
  fi
  delete_remote_ref "refs/heads/${BENCH_GIT_BRANCH}"
  log "bench-git cleanup finished"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd=${1:-setup}
  shift || true
  case "${cmd}" in
    setup) setup_bench_git_server "${1:-.}" ;;
    commit) bench_git_commit "$@" ;;
    cleanup) cleanup_bench_git_branch ;;
    *) echo "usage: $0 setup|commit|cleanup" >&2; exit 2 ;;
  esac
fi
