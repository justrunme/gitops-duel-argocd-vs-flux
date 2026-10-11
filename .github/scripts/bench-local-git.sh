#!/usr/bin/env bash
# Manage a temporary GitHub branch for commit→ready measurements.
# Branch name avoids fix/** and main so pushes do not re-trigger this workflow.
# Exports: BENCH_GIT_URL, BENCH_GIT_BRANCH, BENCH_GIT_SRC
set -euo pipefail

BENCH_GIT_SRC=${BENCH_GIT_SRC:-/tmp/gitops-bench-src}
BENCH_GIT_URL=${BENCH_GIT_URL:-${TF_VAR_git_repository_url:-https://github.com/justrunme/gitops-duel-argocd-vs-flux.git}}
BENCH_GIT_BRANCH=${BENCH_GIT_BRANCH:-ci-bench/${GITHUB_RUN_ID:-local-$(date +%s)}}

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
  # Normalize to https://github.com/owner/repo.git
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
    git -c user.email=bench@local -c user.name=bench commit -m "${message} [skip ci]"
    git push -u origin "HEAD:${BENCH_GIT_BRANCH}"
  )
}

setup_bench_git_server() {
  local repo_root=${1:-.}
  require_push_token

  rm -rf "${BENCH_GIT_SRC}"
  mkdir -p "${BENCH_GIT_SRC}"
  mkdir -p "${BENCH_GIT_SRC}/apps"
  cp -a "${repo_root}/apps/argocd" "${BENCH_GIT_SRC}/apps/argocd"
  cp -a "${repo_root}/apps/flux" "${BENCH_GIT_SRC}/apps/flux"

  (
    cd "${BENCH_GIT_SRC}"
    git init -b main >/dev/null
    git -c user.email=bench@local -c user.name=bench add -A
    git -c user.email=bench@local -c user.name=bench commit -m "bench: initial [skip ci]" >/dev/null
  )
  configure_push_remote "${BENCH_GIT_URL}"
  git -C "${BENCH_GIT_SRC}" push -u origin "HEAD:${BENCH_GIT_BRANCH}" --force

  export BENCH_GIT_URL BENCH_GIT_BRANCH BENCH_GIT_SRC
  log "bench-git ready: ${BENCH_GIT_URL} @ ${BENCH_GIT_BRANCH}"
}

cleanup_bench_git_branch() {
  if [ -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]; then
    return 0
  fi
  if [ -d "${BENCH_GIT_SRC}/.git" ]; then
    git -C "${BENCH_GIT_SRC}" push origin --delete "${BENCH_GIT_BRANCH}" >/dev/null 2>&1 || true
  else
    # Best-effort delete via gh when worktree is gone
    gh api -X DELETE "repos/${GITHUB_REPOSITORY}/git/refs/heads/${BENCH_GIT_BRANCH}" >/dev/null 2>&1 || true
  fi
  log "bench-git cleaned branch ${BENCH_GIT_BRANCH}"
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
