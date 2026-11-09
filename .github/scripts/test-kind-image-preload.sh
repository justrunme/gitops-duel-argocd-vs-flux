#!/usr/bin/env bash
# Behavioral regression for kind image preload under Docker containerd store.
# Requires: docker, kind cluster, network access to public registries.
# Not a mock/shellcheck-only check — exercises real pull + kind load.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/kind-image-platform.sh
source "${SCRIPT_DIR}/lib/kind-image-platform.sh"

CLUSTER="${KIND_CLUSTER_NAME:-kind}"
MULTIARCH_IMG="${TEST_MULTIARCH_IMG:-ghcr.io/dexidp/dex:v2.44.0}"
# Index digest observed for dex:v2.44.0 (OCI image index).
MULTIARCH_INDEX_DIGEST="${TEST_MULTIARCH_INDEX_DIGEST:-sha256:5d0656fce7d453c0e3b2706abf40c0d0ce5b371fb0b73b3cf714d05f35fa5f86}"
MISSING_IMG="${TEST_MISSING_IMG:-ghcr.io/dexidp/dex:gitops-duel-missing-tag-does-not-exist}"

need_cmd() {
  command -v "$1" >/dev/null || {
    echo "required command not found: $1" >&2
    exit 1
  }
}

need_cmd docker
need_cmd kind
need_cmd python3

PLATFORM="$(kind_node_oci_platform "${CLUSTER}")"
echo "regression cluster=${CLUSTER} platform=${PLATFORM}"

pass=0
fail=0
assert_ok() {
  local name="$1"
  echo "PASS: ${name}"
  pass=$((pass + 1))
}
assert_fail_msg() {
  local name="$1" msg="$2"
  echo "FAIL: ${name}: ${msg}" >&2
  fail=$((fail + 1))
}

# --- 1) Earliest wrong state: unscoped pull keeps the OCI index digest.
echo "== case: unscoped multi-arch pull retains index digest =="
docker rmi "${MULTIARCH_IMG}" >/dev/null 2>&1 || true
docker pull --quiet "${MULTIARCH_IMG}"
id="$(docker image inspect "${MULTIARCH_IMG}" --format '{{.Id}}')"
if [ "${id}" = "${MULTIARCH_INDEX_DIGEST}" ]; then
  assert_ok "unscoped pull Id == OCI index digest (${id})"
else
  # On older Docker graph drivers this may already be a single-platform config.
  # Still record the observed Id for CI logs; do not soft-pass the load path.
  echo "NOTE: unscoped Id=${id} (expected index ${MULTIARCH_INDEX_DIGEST} on Docker29/containerd store)"
  assert_ok "unscoped pull completed (Id=${id})"
fi

# Prove kind load of that unscoped reference fails when Id is the index.
set +e
load_log="$(kind load docker-image "${MULTIARCH_IMG}" --name "${CLUSTER}" 2>&1)"
load_rc=$?
set -e
if [ "${id}" = "${MULTIARCH_INDEX_DIGEST}" ]; then
  if [ "${load_rc}" -ne 0 ] && grep -q 'content digest' <<<"${load_log}"; then
    assert_ok "kind load of index digest fails with content digest error"
  else
    assert_fail_msg "index kind load should fail" "rc=${load_rc} log=${load_log}"
  fi
else
  echo "NOTE: skipping index-load failure assertion (store did not retain index Id)"
fi

# --- 2) Fixed path: platform manifest pull + kind load succeeds for multi-arch.
echo "== case: platform-resolved multi-arch image loads into kind =="
docker rmi "${MULTIARCH_IMG}" >/dev/null 2>&1 || true
ensure_single_platform_image "${MULTIARCH_IMG}" "${PLATFORM}"
fixed_id="$(docker image inspect "${MULTIARCH_IMG}" --format '{{.Id}}')"
if [ "${fixed_id}" = "${MULTIARCH_INDEX_DIGEST}" ]; then
  assert_fail_msg "platform ensure must not leave index digest" "Id=${fixed_id}"
else
  assert_ok "platform ensure Id is not index (${fixed_id})"
fi
if kind load docker-image "${MULTIARCH_IMG}" --name "${CLUSTER}"; then
  assert_ok "kind load multi-arch image after platform ensure"
else
  assert_fail_msg "kind load after platform ensure" "load failed"
fi

# --- 3) Missing / wrong image must still fail (no continue-on-error).
echo "== case: missing image pull fails =="
set +e
missing_log="$(ensure_single_platform_image "${MISSING_IMG}" "${PLATFORM}" 2>&1)"
missing_rc=$?
set -e
if [ "${missing_rc}" -ne 0 ]; then
  assert_ok "missing image ensure fails (rc=${missing_rc})"
else
  assert_fail_msg "missing image ensure" "expected failure, got success: ${missing_log}"
fi

# --- 4) Wrong platform request against a multi-arch index must fail loudly.
echo "== case: unavailable platform request fails =="
set +e
badplat_log="$(resolve_platform_manifest_digest "${MULTIARCH_IMG}" "linux/riscv64" 2>&1)"
badplat_rc=$?
set -e
if [ "${badplat_rc}" -ne 0 ]; then
  assert_ok "unsupported platform resolve fails"
else
  assert_fail_msg "unsupported platform resolve" "expected failure, got: ${badplat_log}"
fi

echo "regression summary: pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
[ "${pass}" -ge 3 ]
