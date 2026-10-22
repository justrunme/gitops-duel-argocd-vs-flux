#!/usr/bin/env bash
# Pre-pull the Argo CD chart images on the runner (with retries) and load them
# into the kind node, so the Helm install does not depend on in-cluster pulls.
set -euo pipefail
CHART_VERSION="${ARGOCD_CHART_VERSION:?ARGOCD_CHART_VERSION is required}"
CLUSTER="${KIND_CLUSTER_NAME:-kind}"

mapfile -t images < <(helm template argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version "${CHART_VERSION}" \
  --set redis.image.repository=mirror.gcr.io/library/redis \
  --set redis.image.tag=7.2.11-alpine \
  | awk '$1 == "image:" {gsub(/"/, "", $2); print $2}' | sort -u)
[ "${#images[@]}" -gt 0 ] || { echo "no images found in argo-cd ${CHART_VERSION}" >&2; exit 1; }

for img in "${images[@]}"; do
  for attempt in 1 2 3 4 5; do
    start=$(date +%s)
    if docker pull --quiet "${img}"; then
      echo "pulled ${img} in $(( $(date +%s) - start ))s (attempt ${attempt})"
      break
    fi
    echo "pull of ${img} failed (attempt ${attempt})" >&2
    [ "${attempt}" -eq 5 ] && exit 1
    sleep $(( attempt * 10 ))
  done
  kind load docker-image "${img}" --name "${CLUSTER}"
done
