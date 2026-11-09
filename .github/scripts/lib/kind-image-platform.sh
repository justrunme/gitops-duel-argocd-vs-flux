#!/usr/bin/env bash
# Helpers for loading registry images into kind under Docker's containerd
# image store (Docker 29+), where an unscoped pull of a multi-arch tag keeps
# the OCI index digest locally. kind load then runs
# `ctr images import --all-platforms`, which fails on missing sibling
# platform blobs (e.g. linux/arm/v7) even though the registry is healthy.
#
# Strategy: resolve the kind node platform, pull the matching platform
# manifest by digest, retag to the original reference, then kind load.
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
resolve_platform_manifest_digest() {
  local img="${1:?image required}"
  local platform="${2:?platform required}"
  local raw
  raw="$(docker buildx imagetools inspect --raw "${img}")"
  IMAGE_REF="${img}" PLATFORM="${platform}" python3 -c '
import json, os, sys

idx = json.loads(sys.stdin.read())
media = idx.get("mediaType") or ""
platform = os.environ["PLATFORM"]
parts = platform.split("/")
if len(parts) < 2:
    raise SystemExit(f"invalid platform {platform!r}")
want_os, want_arch = parts[0], parts[1]
want_variant = parts[2] if len(parts) > 2 else None

index_types = {
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
}
if media not in index_types and "manifests" not in idx:
    # Single-platform image manifest: no digest rewrite needed.
    sys.exit(0)

matches = []
for m in idx.get("manifests") or []:
    p = m.get("platform") or {}
    if p.get("os") == "unknown" or p.get("architecture") == "unknown":
        continue
    if p.get("os") != want_os or p.get("architecture") != want_arch:
        continue
    variant = p.get("variant") or None
    if want_variant is not None:
        if variant != want_variant:
            continue
    elif variant:
        # Requested linux/amd64 or linux/arm64: skip arm/v7 etc.
        continue
    digest = m.get("digest")
    if digest:
        matches.append(digest)

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
  local repo digest
  repo="$(image_repository "${img}")"
  digest="$(resolve_platform_manifest_digest "${img}" "${platform}")"
  if [ -n "${digest}" ]; then
    echo "resolved ${img} ${platform} -> ${repo}@${digest}"
    docker pull --quiet "${repo}@${digest}"
    docker tag "${repo}@${digest}" "${img}"
  else
    echo "single-platform pull ${img}"
    docker pull --quiet "${img}"
  fi
}
