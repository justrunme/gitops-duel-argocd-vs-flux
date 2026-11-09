#!/usr/bin/env bash
# Pre-pull the Argo CD chart images on the runner (with retries) and load them
# into the kind node, so the Helm install does not depend on in-cluster pulls.
#
# Under Docker 29's containerd image store, an unscoped pull of a multi-arch
# tag retains the OCI index digest. kind load then imports --all-platforms and
# fails on sibling platform digests that were never pulled. Pull the kind-node
# platform manifest by digest before loading (see lib/kind-image-platform.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/kind-image-platform.sh
source "${SCRIPT_DIR}/lib/kind-image-platform.sh"

CHART_VERSION="${ARGOCD_CHART_VERSION:?ARGOCD_CHART_VERSION is required}"
CLUSTER="${KIND_CLUSTER_NAME:-kind}"
PLATFORM="${KIND_NODE_OCI_PLATFORM:-}"
if [ -z "${PLATFORM}" ]; then
  PLATFORM="$(kind_node_oci_platform "${CLUSTER}")"
fi
echo "kind cluster=${CLUSTER} platform=${PLATFORM}"

mapfile -t images < <(helm template argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version "${CHART_VERSION}" \
  --set redis.image.repository=mirror.gcr.io/library/redis \
  --set redis.image.tag=7.2.11-alpine \
  | awk '$1 == "image:" {gsub(/"/, "", $2); print $2}' | sort -u)
[ "${#images[@]}" -gt 0 ] || { echo "no images found in argo-cd ${CHART_VERSION}" >&2; exit 1; }

for img in "${images[@]}"; do
  for attempt in 1 2 3 4 5; do
    start=$(date +%s)
    if ensure_single_platform_image "${img}" "${PLATFORM}"; then
      echo "pulled ${img} (${PLATFORM}) in $(( $(date +%s) - start ))s (attempt ${attempt})"
      break
    fi
    echo "pull of ${img} failed (attempt ${attempt})" >&2
    [ "${attempt}" -eq 5 ] && exit 1
    sleep $(( attempt * 10 ))
  done
  kind load docker-image "${img}" --name "${CLUSTER}"
done
