#!/bin/bash
# Build CubeSandbox-compatible Hakim images (`cube-hakim-<variant>`).
#
# A cube image is the matching `hakim-<variant>` image plus the pinned
# CubeSandbox envd runtime, tini and the Xvfb/Vulkan packages. See
# devcontainers/cube/Dockerfile and docs/cube-images.md.
#
# Immutability: tags must be unique. The script refuses to build tag `latest`
# and refuses to push a tag that already exists in the registry, so a working
# pilot tag is never overwritten.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REGISTRY="${REGISTRY:-ghcr.io/shekohex}"
CUBE_VARIANTS="${CUBE_VARIANTS:-js}"
CUBE_TAG="${CUBE_TAG:-}"
HAKIM_TAG="${HAKIM_TAG:-}"
CUBESANDBOX_BASE="${CUBESANDBOX_BASE:-}"
BUILDX_BUILDER="${BUILDX_BUILDER:-}"
PUSH_IMAGES=false
HAKIM_COMMIT="${HAKIM_COMMIT:-$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)}"

declare -a BUILT_TAGS=()

function usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Builds cube-hakim-<variant> images from existing hakim-<variant> images.

Options:
  --registry <registry>        Image registry/namespace (default: ghcr.io/shekohex)
  --variants <list>            Comma-separated variants or 'all' (default: js)
  --tag <tag>                  Immutable cube tag (default: cube-<sha>-<utc stamp>)
  --hakim-tag <tag-or-digest>  Existing immutable source tag or digest (required)
  --hakim-commit <sha>         Revision recorded in OCI labels (default: git HEAD)
  --cubesandbox-base <ref>     Override the pinned CubeSandbox base image ref
  --builder <name>             Buildx builder to use
  --push                       Push the immutable tags after building
  --help, -h                   Show this help message

Environment:
  CUBESANDBOX_BASE=<ref>          Override the pinned CubeSandbox base image
  CUBE_ALLOW_TAG_OVERWRITE=true   Permit pushing a tag that already exists
EOF
}

function log() {
  echo "[cube][$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

function error() {
  echo "[cube][ERROR] $*" >&2
}

function require_option_value() {
  local option="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" = "-" ]]; then
    error "$option requires a value"
    exit 2
  fi
}

function source_image_ref() {
  local variant="$1" source_ref="$2"
  if [[ "$source_ref" == @* ]]; then
    printf '%s/hakim-%s%s\n' "$REGISTRY" "$variant" "$source_ref"
  elif [[ "$source_ref" == sha256:* ]]; then
    printf '%s/hakim-%s@%s\n' "$REGISTRY" "$variant" "$source_ref"
  else
    printf '%s/hakim-%s:%s\n' "$REGISTRY" "$variant" "$source_ref"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --registry)
    require_option_value "$1" "${2:-}"
    REGISTRY="$2"
    shift 2
    continue
    ;;
  --variants)
    require_option_value "$1" "${2:-}"
    CUBE_VARIANTS="$2"
    shift 2
    continue
    ;;
  --tag)
    require_option_value "$1" "${2:-}"
    CUBE_TAG="$2"
    shift 2
    continue
    ;;
  --hakim-tag)
    require_option_value "$1" "${2:-}"
    HAKIM_TAG="$2"
    shift 2
    continue
    ;;
  --hakim-commit)
    require_option_value "$1" "${2:-}"
    HAKIM_COMMIT="$2"
    shift 2
    continue
    ;;
  --cubesandbox-base)
    require_option_value "$1" "${2:-}"
    CUBESANDBOX_BASE="$2"
    shift 2
    continue
    ;;
  --builder)
    require_option_value "$1" "${2:-}"
    BUILDX_BUILDER="$2"
    shift 2
    continue
    ;;
  --push)
    PUSH_IMAGES=true
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    error "unknown argument: $1"
    usage
    exit 2
    ;;
  esac
  shift
done

if [[ "$REGISTRY" =~ ^https?:// ]]; then
  REGISTRY="${REGISTRY#http://}"
  REGISTRY="${REGISTRY#https://}"
fi
REGISTRY="${REGISTRY%/}"

if [ -z "$CUBE_TAG" ]; then
  CUBE_TAG="cube-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)-$(date -u +%Y%m%d%H%M%S)"
fi

if [ -z "$HAKIM_TAG" ]; then
  error "--hakim-tag (or HAKIM_TAG) is required; it must identify an existing immutable hakim image"
  exit 2
fi

if [ "$CUBE_TAG" = "latest" ]; then
  error "refusing to build immutable tag 'latest'"
  exit 1
fi

CUBESANDBOX_BASE_ARG=()
if [ -n "$CUBESANDBOX_BASE" ]; then
  CUBESANDBOX_BASE_ARG=(--build-arg "CUBESANDBOX_BASE=$CUBESANDBOX_BASE")
fi

BUILDER_ARGS=()
if [ -n "$BUILDX_BUILDER" ]; then
  BUILDER_ARGS=(--builder "$BUILDX_BUILDER")
fi

mapfile -t ALL_VARIANTS < <(ls -d "$ROOT_DIR"/devcontainers/.devcontainer/images/*/ 2>/dev/null | xargs -n1 basename | sort)

if [ "$CUBE_VARIANTS" = "all" ]; then
  mapfile -t VARIANTS < <(printf '%s\n' "${ALL_VARIANTS[@]}")
else
  IFS=',' read -r -a VARIANTS <<<"$CUBE_VARIANTS"
fi

log "registry:        $REGISTRY"
log "cube tag:        $CUBE_TAG"
log "source hakim tag: $HAKIM_TAG"
log "variants:        ${VARIANTS[*]}"
log "hakim commit:    $HAKIM_COMMIT"

for variant in "${VARIANTS[@]}"; do
  variant="$(echo "$variant" | xargs)"
  [ -n "$variant" ] || continue

  if ! printf '%s\n' "${ALL_VARIANTS[@]}" | grep -qx "$variant"; then
    error "unknown variant '$variant' (known: ${ALL_VARIANTS[*]})"
    exit 1
  fi

  cube_ref="$REGISTRY/cube-hakim-$variant:$CUBE_TAG"
  hakim_ref="$(source_image_ref "$variant" "$HAKIM_TAG")"

  if [ "$PUSH_IMAGES" = true ]; then
    if [ "${CUBE_ALLOW_TAG_OVERWRITE:-false}" != "true" ] && \
      docker buildx imagetools inspect "$cube_ref" >/dev/null 2>&1; then
      error "$cube_ref already exists; pick a new immutable tag"
      exit 1
    fi
  fi

  log "building $cube_ref from $hakim_ref"
  docker buildx build \
    "${BUILDER_ARGS[@]}" \
    --load \
    "${CUBESANDBOX_BASE_ARG[@]}" \
    --build-arg "HAKIM_IMAGE=$hakim_ref" \
    --build-arg "HAKIM_VARIANT=$variant" \
    --build-arg "HAKIM_COMMIT=$HAKIM_COMMIT" \
    -f "$ROOT_DIR/devcontainers/cube/Dockerfile" \
    -t "$cube_ref" \
    "$ROOT_DIR/devcontainers/cube"

  image_id="$(docker image inspect --format '{{.Id}}' "$cube_ref")"
  log "built $cube_ref (image id $image_id)"

  if [ "$PUSH_IMAGES" = true ]; then
    log "pushing $cube_ref"
    docker push "$cube_ref"
    repo_digest="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$cube_ref" | grep "^$REGISTRY/cube-hakim-$variant@" | head -n1 || true)"
    if [ -n "$repo_digest" ]; then
      log "pushed $repo_digest"
    else
      log "pushed $cube_ref (digest unavailable; run: docker buildx imagetools inspect $cube_ref)"
    fi
  fi

  BUILT_TAGS+=("$cube_ref")
done

log "done"
for tag in "${BUILT_TAGS[@]}"; do
  echo "$tag"
done
