#!/usr/bin/env bash
# Manage a temporary GitHub branch for commit→ready measurements.
# Branch prefix: ci/bench-<run-id> (not under fix/** or main, so pushes do not re-trigger CI).
# Exports: BENCH_GIT_URL, BENCH_GIT_BRANCH, BENCH_GIT_SRC
set -euo pipefail

BENCH_GIT_SRC=${BENCH_GIT_SRC:-/tmp/gitops-bench-src}
BENCH_GIT_URL=${BENCH_GIT_URL:-${TF_VAR_git_repository_url:-https://github.com/justrunme/gitops-duel-argocd-vs-flux.git}}
BENCH_GIT_BRANCH=${BENCH_GIT_BRANCH:-ci/bench-${GITHUB_RUN_ID:-local-$(date +%s)}}

# Commits on the temporary branch use the repo owner identity (branch is deleted after the job).
BENCH_GIT_AUTHOR_NAME=${BENCH_GIT_AUTHOR_NAME:-Andrey Lesnikov}
BENCH_GIT_AUTHOR_EMAIL=${BENCH_GIT_AUTHOR_EMAIL:-52860508+justrunme@users.noreply.github.com}

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
    git \
      -c user.name="${BENCH_GIT_AUTHOR_NAME}" \
      -c user.email="${BENCH_GIT_AUTHOR_EMAIL}" \
      commit -m "${message} [skip ci]"
    git push -u origin "HEAD:${BENCH_GIT_BRANCH}"
  )
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
  git -C "${BENCH_GIT_SRC}" push -u origin "HEAD:${BENCH_GIT_BRANCH}" --force

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
  log "Deleting remote branch ${branch}"
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    gh api -X DELETE "repos/${GITHUB_REPOSITORY}/git/refs/heads/${branch}" >/dev/null 2>&1 || true
  fi
  if [ -d "${BENCH_GIT_SRC:-/nonexistent}/.git" ]; then
    git -C "${BENCH_GIT_SRC}" push origin --delete "${branch}" >/dev/null 2>&1 || true
  fi
}

cleanup_bench_git_branch() {
  if [ -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]; then
    log "bench-git cleanup skipped: no GITHUB_TOKEN"
    return 0
  fi

  # Primary: this run's conventional branch
  if [ -n "${BENCH_GIT_BRANCH:-}" ]; then
    delete_remote_ref "refs/heads/${BENCH_GIT_BRANCH}"
  elif [ -n "${GITHUB_RUN_ID:-}" ]; then
    delete_remote_ref "refs/heads/ci/bench-${GITHUB_RUN_ID}"
  fi

  # Sweep leftovers: legacy ci-bench/* and any ci/bench-* for this run / orphans
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    local ref
    for ref in $(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/heads/ci-bench" --jq '.[].ref' 2>/dev/null || true); do
      delete_remote_ref "${ref}"
    done
    for ref in $(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/heads/ci/bench-" --jq '.[].ref' 2>/dev/null || true); do
      delete_remote_ref "${ref}"
    done
  fi
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
