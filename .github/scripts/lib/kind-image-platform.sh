#!/usr/bin/env bash
# Helpers for loading registry images into kind under Docker's containerd
# image store (Docker 29+), where an unscoped pull of a multi-arch tag keeps
# the OCI index digest locally. kind load then runs
# `ctr images import --all-platforms`, which fails on missing sibling
# platform blobs (e.g. linux/arm/v7) even though the registry is healthy.
#
# Strategy: resolve the kind node platform, pull the matching platform
# manifest by digest, retag to the original reference, then kind load.
#
# NOTE: when this function is invoked from `if ensure_...; then`, Bash
# disables errexit inside the function body. Every fallible step must
# check status explicitly and return non-zero — never fall through to a
# plain-pull "success" after resolve/pull/tag failure.
set -euo pipefail

kind_node_name() {
  local cluster="${1:?cluster name required}"
  local node
  node="$(kind get nodes --name "${cluster}" | head -n1)"
  [ -n "${node}" ] || {
    echo "no kind nodes found for cluster ${cluster}" >&2
    return 1
  }
  printf '%s\n' "${node}"
}

# Map kind node uname -m to an OCI platform string (os/arch).
kind_node_oci_platform() {
  local cluster="${1:?cluster name required}"
  local node machine
  node="$(kind_node_name "${cluster}")"
  machine="$(docker exec "${node}" uname -m)"
  case "${machine}" in
    x86_64 | amd64) printf 'linux/amd64\n' ;;
    aarch64 | arm64) printf 'linux/arm64\n' ;;
    armv7l | armhf) printf 'linux/arm/v7\n' ;;
    *)
      echo "unsupported kind node architecture: ${machine}" >&2
      return 1
      ;;
  esac
}

# Repository path without tag or digest (ghcr.io/dexidp/dex).
image_repository() {
  local img="${1:?image required}"
  if [[ "${img}" == *"@"* ]]; then
    printf '%s\n' "${img%@*}"
    return 0
  fi
  local name="${img##*/}"
  if [[ "${name}" == *:* ]]; then
    printf '%s\n' "${img%:*}"
  else
    printf '%s\n' "${img}"
  fi
}

# Return the platform manifest digest for an index/list, or empty for a
# single-platform manifest (caller should plain-pull the reference).
# Exits non-zero when metadata cannot be read or the requested platform
# is absent — callers must not treat that as "plain-pull OK".
resolve_platform_manifest_digest() {
  local img="${1:?image required}"
  local platform="${2:?platform required}"
  local raw
  raw="$(docker buildx imagetools inspect --raw "${img}")" || {
    echo "failed to inspect image manifest for ${img}" >&2
    return 1
  }
  IMAGE_REF="${img}" PLATFORM="${platform}" python3 -c '
import json, os, sys

idx = json.loads(sys.stdin.read())
media = idx.get("mediaType") or ""
platform = os.environ["PLATFORM"]
parts = platform.split("/")
if len(parts) < 2:
    raise SystemExit("invalid platform %r" % (platform,))
want_os, want_arch = parts[0], parts[1]
want_variant = parts[2] if len(parts) > 2 else None

index_types = {
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
}
if media not in index_types and "manifests" not in idx:
    # Single-platform image manifest: no digest rewrite needed.
    sys.exit(0)

exact = []
arm64_v8 = []
for m in idx.get("manifests") or []:
    p = m.get("platform") or {}
    if p.get("os") == "unknown" or p.get("architecture") == "unknown":
        continue
    if p.get("os") != want_os or p.get("architecture") != want_arch:
        continue
    variant = p.get("variant") or None
    digest = m.get("digest")
    if not digest:
        continue
    if want_variant is not None:
        if variant == want_variant:
            exact.append(digest)
        continue
    # Requested linux/<arch> with no variant pin:
    if variant is None:
        exact.append(digest)
    elif want_arch == "arm64" and variant == "v8":
        # OCI often labels arm64 as linux/arm64/v8 (e.g. official redis).
        arm64_v8.append(digest)
    # Other variants (arm/v7, arm/v6, ...) never match bare linux/arm64.

matches = exact or arm64_v8
if not matches:
    raise SystemExit(
        "no platform manifest for %s in %s" % (platform, os.environ["IMAGE_REF"])
    )
print(matches[0])
' <<<"${raw}"
}

# Pull so the local docker reference is a single-platform image suitable for
# `kind load docker-image` (not an incomplete multi-arch index).
ensure_single_platform_image() {
  local img="${1:?image required}"
  local platform="${2:?platform required}"
  local repo digest resolve_rc pull_rc tag_rc

  repo="$(image_repository "${img}")"

  # Explicit status: command substitution under `if fn; then` does not
  # trip errexit when the inner command fails.
  digest="$(resolve_platform_manifest_digest "${img}" "${platform}")" && resolve_rc=$? || resolve_rc=$?
  if [ "${resolve_rc}" -ne 0 ]; then
    echo "platform manifest resolution failed for ${img} (${platform})" >&2
    return "${resolve_rc}"
  fi

  if [ -n "${digest}" ]; then
    echo "resolved ${img} ${platform} -> ${repo}@${digest}"
    docker pull --quiet "${repo}@${digest}" && pull_rc=$? || pull_rc=$?
    if [ "${pull_rc}" -ne 0 ]; then
      echo "docker pull failed for ${repo}@${digest}" >&2
      return "${pull_rc}"
    fi
    docker tag "${repo}@${digest}" "${img}" && tag_rc=$? || tag_rc=$?
    if [ "${tag_rc}" -ne 0 ]; then
      echo "docker tag failed for ${repo}@${digest} -> ${img}" >&2
      return "${tag_rc}"
    fi
  else
    echo "single-platform pull ${img}"
    docker pull --quiet "${img}" && pull_rc=$? || pull_rc=$?
    if [ "${pull_rc}" -ne 0 ]; then
      echo "docker pull failed for ${img}" >&2
      return "${pull_rc}"
    fi
  fi
}
