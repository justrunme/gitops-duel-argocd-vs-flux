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
# Index digest observed for dex:v2.44.0 on Docker29/containerd store (evidence).
MULTIARCH_INDEX_DIGEST="${TEST_MULTIARCH_INDEX_DIGEST:-sha256:5d0656fce7d453c0e3b2706abf40c0d0ce5b371fb0b73b3cf714d05f35fa5f86}"
MISSING_IMG="${TEST_MISSING_IMG:-ghcr.io/dexidp/dex:gitops-duel-missing-tag-does-not-exist}"
# Chart image known to publish linux/arm64/v8 (not bare linux/arm64).
ARM64_V8_IMG="${TEST_ARM64_V8_IMG:-mirror.gcr.io/library/redis:7.2.11-alpine}"

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

# --- 1) Evidence-only: record unscoped multi-arch pull / kind load behavior.
# Do NOT require the upstream index-load bug to remain forever.
echo "== case: evidence unscoped multi-arch pull (non-gating) =="
docker rmi "${MULTIARCH_IMG}" >/dev/null 2>&1 || true
docker pull --quiet "${MULTIARCH_IMG}"
id="$(docker image inspect "${MULTIARCH_IMG}" --format '{{.Id}}')"
echo "EVIDENCE: unscoped pull Id=${id}"
if [ "${id}" = "${MULTIARCH_INDEX_DIGEST}" ]; then
  echo "EVIDENCE: matches known Docker29 index digest ${MULTIARCH_INDEX_DIGEST}"
else
  echo "EVIDENCE: Id differs from historical index digest (store/kind may have changed)"
fi
set +e
load_log="$(kind load docker-image "${MULTIARCH_IMG}" --name "${CLUSTER}" 2>&1)"
load_rc=$?
set -e
echo "EVIDENCE: unscoped kind load rc=${load_rc}"
if [ "${load_rc}" -ne 0 ]; then
  echo "EVIDENCE: unscoped kind load error: ${load_log}" | head -n5
fi
assert_ok "recorded unscoped pull/load evidence (non-gating)"

# --- 2) Gating positive: platform-resolved multi-arch image loads into kind.
echo "== case: platform-resolved multi-arch image loads into kind =="
docker rmi "${MULTIARCH_IMG}" >/dev/null 2>&1 || true
if ! ensure_single_platform_image "${MULTIARCH_IMG}" "${PLATFORM}"; then
  assert_fail_msg "platform ensure" "ensure_single_platform_image failed"
else
  fixed_id="$(docker image inspect "${MULTIARCH_IMG}" --format '{{.Id}}')"
  echo "platform-ensure Id=${fixed_id}"
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
fi

# --- 3) Production conditional: valid image + unavailable platform must FAIL.
echo "== case: if ensure(valid image, unavailable platform) must fail =="
set +e
if ensure_single_platform_image "${MULTIARCH_IMG}" "linux/riscv64"; then
  cond_rc=0
else
  cond_rc=$?
fi
set -e
if [ "${cond_rc}" -ne 0 ]; then
  assert_ok "production if-ensure unavailable platform fails (rc=${cond_rc})"
else
  assert_fail_msg "production if-ensure unavailable platform" "returned success (plain-pull fallback?)"
fi

# --- 4) Missing image via production conditional must fail (no success fallback).
echo "== case: if ensure(missing image) must fail =="
set +e
if ensure_single_platform_image "${MISSING_IMG}" "${PLATFORM}"; then
  miss_rc=0
else
  miss_rc=$?
fi
set -e
if [ "${miss_rc}" -ne 0 ]; then
  assert_ok "production if-ensure missing image fails (rc=${miss_rc})"
else
  assert_fail_msg "production if-ensure missing image" "returned success"
fi

# --- 5) Digest-pull failure while a cached tag exists: NOT EXECUTED.
# A PATH-wrapper "docker pull" exit is a simulated CLI fault, not a real
# registry/network failure. Production ensure() still returns non-zero on
# pull/tag failure (explicit rc checks); that branch is code-reviewed but
# not proven here by a genuine Docker/registry fault without adding a
# proxy/fault harness.
echo "== case: digest-pull failure under cached tag =="
echo "NOT_EXECUTED: real docker/registry pull-failure-under-cache (no mock CLI wrapper; no fault proxy)"

# --- 6) Metadata: linux/arm64 must resolve redis arm64/v8 (chart image), never amd64/unknown.
echo "== case: arm64 resolver accepts arm64/v8 for chart redis =="
arm64_digest="$(resolve_platform_manifest_digest "${ARM64_V8_IMG}" "linux/arm64")"
if [ -z "${arm64_digest}" ]; then
  assert_fail_msg "arm64/v8 resolve" "empty digest"
else
  # Confirm resolved digest is the arm64/v8 entry, not amd64.
  raw="$(docker buildx imagetools inspect --raw "${ARM64_V8_IMG}")"
  matched="$(DIGEST="${arm64_digest}" python3 -c '
import json,os,sys
idx=json.load(sys.stdin)
want=os.environ["DIGEST"]
for m in idx.get("manifests") or []:
  if m.get("digest")!=want: continue
  p=m.get("platform") or {}
  print("%s/%s%s" % (p.get("os"), p.get("architecture"), ("/"+p["variant"]) if p.get("variant") else ""))
  break
' <<<"${raw}")"
  echo "resolved ${ARM64_V8_IMG} linux/arm64 -> ${arm64_digest} (${matched})"
  if [ "${matched}" = "linux/arm64/v8" ] || [ "${matched}" = "linux/arm64" ]; then
    assert_ok "arm64 resolve maps to ${matched}"
  else
    assert_fail_msg "arm64 resolve" "unexpected platform ${matched}"
  fi
fi
# Never resolve amd64 when asking arm64 for dex either (sanity).
dex_arm="$(resolve_platform_manifest_digest "${MULTIARCH_IMG}" "linux/arm64")"
dex_amd="$(resolve_platform_manifest_digest "${MULTIARCH_IMG}" "linux/amd64")"
if [ "${dex_arm}" = "${dex_amd}" ]; then
  assert_fail_msg "arm64!=amd64" "dex arm64 digest equals amd64"
else
  assert_ok "dex arm64 digest distinct from amd64"
fi
echo "NOTE: arm64 digest resolution verified from registry metadata; no arm64 kind node in this run"

echo "regression summary: pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
# Gating cases: evidence note + positive load pair + two real negatives + arm64 metadata pair.
[ "${pass}" -ge 6 ]
