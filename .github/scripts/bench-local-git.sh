#!/usr/bin/env bash
# Start an in-cluster dumb-HTTP git server for commit→ready measurements.
# Exports: BENCH_GIT_URL, BENCH_GIT_SRC, BENCH_GIT_BARE
set -euo pipefail

BENCH_GIT_SRC=${BENCH_GIT_SRC:-/tmp/gitops-bench-src}
BENCH_GIT_BARE=${BENCH_GIT_BARE:-/tmp/gitops-bench.git}
BENCH_GIT_NS=${BENCH_GIT_NS:-default}
BENCH_GIT_POD=${BENCH_GIT_POD:-git-httpd}

log() { printf '%s\n' "$*" >&2; }

sync_bare_to_pod() {
  (cd "${BENCH_GIT_BARE}" && git --bare update-server-info)
  kubectl -n "${BENCH_GIT_NS}" exec "${BENCH_GIT_POD}" -- \
    sh -c 'pkill -f "python -m http.server" >/dev/null 2>&1 || true; rm -rf /repo.git'
  kubectl -n "${BENCH_GIT_NS}" cp "${BENCH_GIT_BARE}" "${BENCH_GIT_POD}:/repo.git"
  kubectl -n "${BENCH_GIT_NS}" exec "${BENCH_GIT_POD}" -- \
    sh -c 'cd /repo.git && git --bare update-server-info && nohup python -m http.server 8080 >/tmp/httpd.log 2>&1 &'
  sleep 1
}

bench_git_commit() {
  local message=$1
  shift
  (
    cd "${BENCH_GIT_SRC}"
    git add -A
    if git diff --cached --quiet; then
      log "bench-local-git: nothing to commit (${message})"
      return 0
    fi
    git -c user.email=bench@local -c user.name=bench commit -m "${message}"
    git push "${BENCH_GIT_BARE}" HEAD:main
  )
  sync_bare_to_pod
}

setup_bench_git_server() {
  local repo_root=${1:-.}
  rm -rf "${BENCH_GIT_SRC}" "${BENCH_GIT_BARE}"
  mkdir -p "${BENCH_GIT_SRC}"
  # Minimal tree watched by both tools
  mkdir -p "${BENCH_GIT_SRC}/apps"
  cp -a "${repo_root}/apps/argocd" "${BENCH_GIT_SRC}/apps/argocd"
  cp -a "${repo_root}/apps/flux" "${BENCH_GIT_SRC}/apps/flux"

  (
    cd "${BENCH_GIT_SRC}"
    git init -b main >/dev/null
    git -c user.email=bench@local -c user.name=bench add -A
    git -c user.email=bench@local -c user.name=bench commit -m "bench: initial" >/dev/null
  )
  git clone --bare "${BENCH_GIT_SRC}" "${BENCH_GIT_BARE}" >/dev/null
  (cd "${BENCH_GIT_BARE}" && git --bare update-server-info)

  kubectl -n "${BENCH_GIT_NS}" delete pod "${BENCH_GIT_POD}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl -n "${BENCH_GIT_NS}" delete svc git-httpd --ignore-not-found >/dev/null 2>&1 || true

  kubectl -n "${BENCH_GIT_NS}" run "${BENCH_GIT_POD}" \
    --image=python:3.12-alpine \
    --restart=Never \
    --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
    --command -- sleep 7200 >/dev/null
  kubectl -n "${BENCH_GIT_NS}" wait --for=condition=Ready "pod/${BENCH_GIT_POD}" --timeout=180s >/dev/null

  kubectl -n "${BENCH_GIT_NS}" exec "${BENCH_GIT_POD}" -- \
    sh -c 'apk add --no-cache git >/dev/null'
  sync_bare_to_pod

  # Restart python httpd serving the bare repo
  kubectl -n "${BENCH_GIT_NS}" exec "${BENCH_GIT_POD}" -- \
    sh -c 'pkill -f "python -m http.server" >/dev/null 2>&1 || true; cd /repo.git && nohup python -m http.server 8080 >/tmp/httpd.log 2>&1 &'
  sleep 1
  kubectl -n "${BENCH_GIT_NS}" expose pod "${BENCH_GIT_POD}" --name=git-httpd --port=8080 --target-port=8080 >/dev/null

  BENCH_GIT_URL="http://git-httpd.${BENCH_GIT_NS}.svc.cluster.local:8080/"
  export BENCH_GIT_URL BENCH_GIT_SRC BENCH_GIT_BARE
  log "bench-local-git ready at ${BENCH_GIT_URL}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd=${1:-setup}
  shift || true
  case "${cmd}" in
    setup) setup_bench_git_server "${1:-.}" ;;
    commit) bench_git_commit "$@" ;;
    sync) sync_bare_to_pod ;;
    *) echo "usage: $0 setup|commit|sync" >&2; exit 2 ;;
  esac
fi
