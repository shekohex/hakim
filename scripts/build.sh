#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/shekohex}"
CACHE_REPO="${CACHE_REPO:-}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
RUN_REF="${RUN_REF:-$TIMESTAMP}"
BUILDX_BUILDER="${BUILDX_BUILDER:-}"
REGISTRY_HTTP="${REGISTRY_HTTP:-false}"

CODER_VERSION=""
CODE_SERVER_VERSION=""
CHROME_VERSION=""
HAKIM_VARIANTS="${HAKIM_VARIANTS:-all}"
CUBE_VARIANTS="${CUBE_VARIANTS:-}"
FETCH_LATEST=false
PUSH_IMAGES=false
DIRECT_PUSH=false

USE_REGISTRY_CACHE_FROM="${USE_REGISTRY_CACHE_FROM:-false}"
USE_REGISTRY_CACHE_TO="${USE_REGISTRY_CACHE_TO:-false}"

declare -a BASE_VERSION_ARGS=()
declare -a BUILT_IMAGE_TAGS=()
declare -a BUILT_CUBE_IMAGE_TAGS=()
declare -a TEMP_CONFIGS=()

function devcontainer() {
  bunx devcontainer "$@"
}

function log() {
  local level="$1"
  shift
  echo "[$(date +"%Y-%m-%d %H:%M:%S")][$level] $*"
}

function info() {
  log "INFO" "$@"
}

function warn() {
  log "WARN" "$@"
}

function error() {
  log "ERROR" "$@"
}

function on_exit() {
  local status=$?
  local file
  if [ ${#TEMP_CONFIGS[@]} -gt 0 ]; then
    for file in "${TEMP_CONFIGS[@]}"; do
      rm -f "$file"
    done
  fi
  if [ $status -eq 0 ]; then
    info "Build completed successfully"
  else
    error "Build failed with exit code $status"
  fi
}

trap on_exit EXIT

function fetch_latest_version() {
  local repo="$1"
  gh release view --repo "$repo" --json tagName -q '.tagName' | sed 's/^v//'
}

function fetch_all_latest_versions() {
  info "Fetching latest tool versions..."
  LATEST_CODER=$(fetch_latest_version "coder/coder")
  LATEST_CODE_SERVER=$(fetch_latest_version "coder/code-server")
  LATEST_CHROME=$(curl -fsSL "https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_STABLE" 2>/dev/null | tr -d '\r')
  info "Latest versions: coder=$LATEST_CODER, code-server=$LATEST_CODE_SERVER, chrome=$LATEST_CHROME"
}

function usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --registry <registry>          Target image registry/namespace (default: ghcr.io/shekohex)
  --cache-repo <repo>            Registry cache repo (default: <registry>/hakim-cache)
  --cache-from-registry          Enable registry cache import
  --cache-to-registry            Enable registry cache export
  --no-registry-cache            Disable registry cache import/export
  --coder-version <version>      Specify the version of coder CLI to install
  --code-version <version>       Specify the version of code-server to install
  --chrome-version <version>     Specify the version of Google Chrome to install
  --variants <list>              Build hakim-<variant> images (comma list or 'all'; default: all)
  --cube-variants <list>         Also build cube-hakim-<variant> images (comma list or 'all')
  --fetch-latest                 Fetch and use latest versions for all tools (requires gh CLI)
  --push                         Push built images after local build
  --builder <name>               Use a specific docker buildx builder
  --registry-http                Configure auto-created builder for HTTP/insecure registry
  --help, -h                     Show this help message

If no version is specified, defaults from Dockerfile are used.
With --fetch-latest, all unspecified versions are resolved to latest.
EOF
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  --registry)
    REGISTRY="$2"
    shift
    ;;
  --cache-repo)
    CACHE_REPO="$2"
    USE_REGISTRY_CACHE_FROM=true
    shift
    ;;
  --cache-from-registry)
    USE_REGISTRY_CACHE_FROM=true
    ;;
  --cache-to-registry)
    USE_REGISTRY_CACHE_TO=true
    ;;
  --no-registry-cache)
    USE_REGISTRY_CACHE_FROM=false
    USE_REGISTRY_CACHE_TO=false
    ;;
  --coder-version)
    CODER_VERSION="$2"
    shift
    ;;
  --code-version)
    CODE_SERVER_VERSION="$2"
    shift
    ;;
  --chrome-version)
    CHROME_VERSION="$2"
    shift
    ;;
  --variants)
    if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" = "-" ]]; then
      echo "--variants requires a value" >&2
      exit 2
    fi
    HAKIM_VARIANTS="$2"
    shift
    ;;
  --cube-variants)
    if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" = "-" ]]; then
      echo "--cube-variants requires a value" >&2
      exit 2
    fi
    CUBE_VARIANTS="$2"
    shift
    ;;
  --fetch-latest) FETCH_LATEST=true ;;
  --push) PUSH_IMAGES=true ;;
  --builder)
    BUILDX_BUILDER="$2"
    shift
    ;;
  --registry-http) REGISTRY_HTTP=true ;;
  --help | -h) usage ;;
  *)
    echo "Unknown parameter passed: $1"
    usage
    ;;
  esac
  shift
done

if [[ "$REGISTRY" =~ ^https?:// ]]; then
  warn "Registry should not include scheme. Stripping it from '$REGISTRY'."
  REGISTRY="${REGISTRY#http://}"
  REGISTRY="${REGISTRY#https://}"
fi
REGISTRY="${REGISTRY%/}"

if [ -z "$REGISTRY" ]; then
  error "Registry cannot be empty"
  exit 1
fi

REGISTRY_HOST="${REGISTRY%%/*}"

if [ -z "$CACHE_REPO" ]; then
  CACHE_REPO="$REGISTRY/hakim-cache"
fi

if [[ "$CACHE_REPO" =~ ^https?:// ]]; then
  warn "Cache repo should not include scheme. Stripping it from '$CACHE_REPO'."
  CACHE_REPO="${CACHE_REPO#http://}"
  CACHE_REPO="${CACHE_REPO#https://}"
fi
CACHE_REPO="${CACHE_REPO%/}"
CACHE_REPO_HOST="${CACHE_REPO%%/*}"

declare -a VARIANT_PATHS=()
if [ "$HAKIM_VARIANTS" = "all" ]; then
  VARIANT_PATHS=(devcontainers/.devcontainer/images/*)
else
  IFS=',' read -r -a REQUESTED_VARIANTS <<<"$HAKIM_VARIANTS"
  for variant_name in "${REQUESTED_VARIANTS[@]}"; do
    variant_name="$(echo "$variant_name" | xargs)"
    [ -n "$variant_name" ] || continue
    variant_path="devcontainers/.devcontainer/images/$variant_name"
    if [ ! -d "$variant_path" ]; then
      error "Unknown Hakim variant: $variant_name"
      exit 2
    fi
    VARIANT_PATHS+=("$variant_path")
  done
fi

if [ ${#VARIANT_PATHS[@]} -eq 0 ]; then
  error "No Hakim variants selected"
  exit 2
fi

if [ "$FETCH_LATEST" = true ]; then
  if ! command -v gh &>/dev/null; then
    error "gh CLI is required for --fetch-latest but not found"
    exit 1
  fi
  fetch_all_latest_versions
  [ -z "$CODER_VERSION" ] && CODER_VERSION="$LATEST_CODER"
  [ -z "$CODE_SERVER_VERSION" ] && CODE_SERVER_VERSION="$LATEST_CODE_SERVER"
  [ -z "$CHROME_VERSION" ] && CHROME_VERSION="$LATEST_CHROME"
fi

if [ -n "$CODER_VERSION" ]; then
  BASE_VERSION_ARGS+=(--build-arg "CODER_VERSION=$CODER_VERSION")
fi
if [ -n "$CODE_SERVER_VERSION" ]; then
  BASE_VERSION_ARGS+=(--build-arg "CODE_SERVER_VERSION=$CODE_SERVER_VERSION")
fi
if [ -n "$CHROME_VERSION" ]; then
  BASE_VERSION_ARGS+=(--build-arg "GOOGLE_CHROME_VERSION=$CHROME_VERSION")
fi

if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  info "Running in GitHub Actions, enabling registry cache import/export and push output."
  USE_REGISTRY_CACHE_FROM=true
  USE_REGISTRY_CACHE_TO=true
fi

if [ "${GITHUB_ACTIONS:-false}" = "true" ] && [ "$PUSH_IMAGES" = true ]; then
  warn "Ignoring --push because GitHub Actions already pushes via buildx --push"
  PUSH_IMAGES=false
fi

if ! docker buildx version >/dev/null 2>&1; then
  error "docker buildx is required"
  exit 1
fi

function current_buildx_builder() {
  docker buildx ls 2>/dev/null | awk 'NR>1 && $1 ~ /\*/ {name=$1; gsub(/\*/, "", name); print name; exit}'
}

function buildx_builder_driver() {
  local builder="$1"
  local inspect_output
  local raw_driver

  if [ -z "$builder" ]; then
    echo ""
    return 0
  fi

  if ! inspect_output="$(docker buildx inspect "$builder" 2>/dev/null)"; then
    echo ""
    return 0
  fi

  raw_driver="$(awk -F':' '/^Driver:/ {print $2; exit}' <<< "$inspect_output")"
  raw_driver="$(echo "$raw_driver" | xargs)"
  echo "$raw_driver"
}

function list_buildx_builders() {
  docker buildx ls 2>/dev/null | awk 'NR>1 && $1 !~ /^\\_/ && $1 != "" {name=$1; gsub(/\*/, "", name); if (name != "NAME/NODE") print name}'
}

function use_existing_prefixed_builder() {
  local prefix="$1"
  local candidate
  local candidate_driver

  for candidate in $(list_buildx_builders); do
    case "$candidate" in
    "$prefix"-[0-9]*)
      candidate_driver="$(buildx_builder_driver "$candidate")"
      if [ "$candidate_driver" = "docker-container" ]; then
        docker buildx use "$candidate" >/dev/null
        export BUILDX_BUILDER="$candidate"
        info "Using buildx builder '$candidate' (driver=$candidate_driver)"
        docker buildx inspect "$candidate" --bootstrap >/dev/null
        return 0
      fi
      ;;
    esac
  done

  return 1
}

function write_buildkit_http_registry_config() {
  local config_file="$1"

  {
    echo "[registry.\"$REGISTRY_HOST\"]"
    echo "  http = true"
    echo "  insecure = true"
    if [ "$CACHE_REPO_HOST" != "$REGISTRY_HOST" ]; then
      echo
      echo "[registry.\"$CACHE_REPO_HOST\"]"
      echo "  http = true"
      echo "  insecure = true"
    fi
  } > "$config_file"
}

function ensure_cache_export_builder() {
  local selected
  local driver
  local candidate
  local candidate_driver
  local created_builder
  local buildkitd_config_file

  if [ "$USE_REGISTRY_CACHE_TO" != "true" ]; then
    if [ -n "$BUILDX_BUILDER" ]; then
      export BUILDX_BUILDER
    fi
    return
  fi

  if [ "$REGISTRY_HTTP" = "true" ] && [ -z "$BUILDX_BUILDER" ]; then
    created_builder="hakim-builder-http"
    if [ "$(buildx_builder_driver "$created_builder")" = "docker-container" ]; then
      docker buildx use "$created_builder" >/dev/null
      export BUILDX_BUILDER="$created_builder"
      info "Using buildx builder '$created_builder' (driver=docker-container)"
      docker buildx inspect "$created_builder" --bootstrap >/dev/null
      return
    fi

    if docker buildx inspect "$created_builder" >/dev/null 2>&1; then
      if use_existing_prefixed_builder "$created_builder"; then
        return
      fi
      created_builder="hakim-builder-http-$RUN_REF"
    fi

    buildkitd_config_file="$(mktemp "/tmp/hakim-buildkitd.${RUN_REF}.XXXXXX.toml")"
    TEMP_CONFIGS+=("$buildkitd_config_file")
    write_buildkit_http_registry_config "$buildkitd_config_file"
    info "Creating buildx builder '$created_builder' with docker-container driver for HTTP registry access"
    docker buildx create --name "$created_builder" --driver docker-container --buildkitd-config "$buildkitd_config_file" --use >/dev/null
    export BUILDX_BUILDER="$created_builder"
    docker buildx inspect "$created_builder" --bootstrap >/dev/null
    info "Using buildx builder '$created_builder' (driver=docker-container)"
    return
  fi

  selected="$BUILDX_BUILDER"
  if [ -z "$selected" ]; then
    selected="$(current_buildx_builder)"
  fi

  if [ -n "$selected" ]; then
    driver="$(buildx_builder_driver "$selected")"
  else
    driver=""
  fi

  if [ "$driver" = "docker-container" ]; then
    export BUILDX_BUILDER="$selected"
    info "Using buildx builder '$selected' (driver=$driver)"
    docker buildx inspect "$selected" --bootstrap >/dev/null
    return
  fi

  if [ -n "$selected" ] && [ "$driver" = "docker" ]; then
    for candidate in $(list_buildx_builders); do
      if [ "$candidate" = "$selected" ]; then
        continue
      fi
      candidate_driver="$(buildx_builder_driver "$candidate")"
      if [ "$candidate_driver" = "docker-container" ]; then
        docker buildx use "$candidate" >/dev/null
        export BUILDX_BUILDER="$candidate"
        info "Switched buildx builder from '$selected' (docker) to '$candidate' (docker-container) for cache export"
        docker buildx inspect "$candidate" --bootstrap >/dev/null
        return
      fi
    done
  fi

  created_builder="hakim-builder"
  if [ "$(buildx_builder_driver "$created_builder")" = "docker-container" ]; then
    docker buildx use "$created_builder" >/dev/null
    export BUILDX_BUILDER="$created_builder"
    info "Using buildx builder '$created_builder' (driver=docker-container)"
    docker buildx inspect "$created_builder" --bootstrap >/dev/null
    return
  fi

  if docker buildx inspect "$created_builder" >/dev/null 2>&1; then
    if use_existing_prefixed_builder "$created_builder"; then
      return
    fi
    created_builder="hakim-builder-$RUN_REF"
  fi

  info "Creating buildx builder '$created_builder' with docker-container driver for cache export"
  docker buildx create --name "$created_builder" --driver docker-container --use >/dev/null
  export BUILDX_BUILDER="$created_builder"
  docker buildx inspect "$created_builder" --bootstrap >/dev/null
  info "Using buildx builder '$created_builder' (driver=docker-container)"
}

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if command -v gh &>/dev/null; then
    info "Attempting to fetch GITHUB_TOKEN from gh CLI..."
    if TOKEN=$(gh auth token 2>/dev/null); then
      export GITHUB_TOKEN="$TOKEN"
      info "Successfully loaded GITHUB_TOKEN from gh CLI."
    else
      warn "gh CLI found but failed to get token. You may hit GitHub rate limits."
    fi
  else
    warn "gh CLI not found and GITHUB_TOKEN not set. You may hit GitHub rate limits."
    warn "Install gh CLI or set GITHUB_TOKEN to avoid this."
  fi
else
  info "GITHUB_TOKEN is already set."
fi

ensure_cache_export_builder

declare -a BUILDX_ARGS=()
if [ -n "${BUILDX_BUILDER:-}" ]; then
  BUILDX_ARGS=(--builder "$BUILDX_BUILDER")
fi

ACTIVE_BUILDX_DRIVER="$(buildx_builder_driver "${BUILDX_BUILDER:-$(current_buildx_builder)}")"
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  DIRECT_PUSH=true
elif [ "$PUSH_IMAGES" = true ] && [ "$ACTIVE_BUILDX_DRIVER" = "docker-container" ]; then
  DIRECT_PUSH=true
  info "Using direct registry push during build because builder driver is docker-container"
fi

declare -a BUILD_OUTPUT_ARGS=("--load")
if [ "$DIRECT_PUSH" = "true" ]; then
  BUILD_OUTPUT_ARGS=("--push")
fi

declare -a SECRET_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  SECRET_ARGS+=(--secret "id=github_token,env=GITHUB_TOKEN")
fi

function populate_cache_args() {
  local scope="$1"
  local -n args_ref="$2"
  args_ref=()

  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    args_ref+=(--cache-from "type=gha,scope=${scope}")
    args_ref+=(--cache-to "type=gha,mode=max,scope=${scope}")
  fi

  if [ "$USE_REGISTRY_CACHE_FROM" = "true" ]; then
    args_ref+=(--cache-from "type=registry,ref=${CACHE_REPO}:${scope}")
  fi

  if [ "$USE_REGISTRY_CACHE_TO" = "true" ]; then
    args_ref+=(--cache-to "type=registry,ref=${CACHE_REPO}:${scope},mode=max,ignore-error=true")
  fi
}

function add_image_tags() {
  local image_name="$1"
  BUILT_IMAGE_TAGS+=("$REGISTRY/$image_name:latest")
  BUILT_IMAGE_TAGS+=("$REGISTRY/$image_name:$RUN_REF")
}

function push_built_images() {
  local image
  info "Pushing built images to $REGISTRY..."
  for image in "${BUILT_IMAGE_TAGS[@]}"; do
    info "Pushing $image"
    docker push "$image"
  done
  for image in "${BUILT_CUBE_IMAGE_TAGS[@]}"; do
    info "Pushing $image"
    docker push "$image"
  done
}

BASE_IMAGE_REF="$REGISTRY/hakim-base:$RUN_REF"
TOOLING_IMAGE_REF="$REGISTRY/hakim-tooling:$RUN_REF"

info "Using run ref: $RUN_REF"
info "Using cache repo: $CACHE_REPO"
info "Registry cache import: $USE_REGISTRY_CACHE_FROM"
info "Registry cache export: $USE_REGISTRY_CACHE_TO"
info "Buildx driver: ${ACTIVE_BUILDX_DRIVER:-unknown}"
info "Direct build push: $DIRECT_PUSH"

populate_cache_args "base" BASE_CACHE_ARGS
info "Building Base Image..."
docker buildx build \
  "${BUILDX_ARGS[@]}" \
  "${BUILD_OUTPUT_ARGS[@]}" \
  "${SECRET_ARGS[@]}" \
  "${BASE_CACHE_ARGS[@]}" \
  "${BASE_VERSION_ARGS[@]}" \
  -t "$REGISTRY/hakim-base:latest" \
  -t "$BASE_IMAGE_REF" \
  devcontainers/base
add_image_tags "hakim-base"

populate_cache_args "tooling" TOOLING_CACHE_ARGS
info "Building Tooling Image..."
docker buildx build \
  "${BUILDX_ARGS[@]}" \
  "${BUILD_OUTPUT_ARGS[@]}" \
  "${SECRET_ARGS[@]}" \
  "${TOOLING_CACHE_ARGS[@]}" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE_REF" \
  -t "$REGISTRY/hakim-tooling:latest" \
  -t "$TOOLING_IMAGE_REF" \
  devcontainers/tooling
add_image_tags "hakim-tooling"

for variant in "${VARIANT_PATHS[@]}"; do
  variant_name=$(basename "$variant")
  info "Building Variant: $variant_name..."

  tmp_config=$(mktemp "${variant}/.devcontainer/.tmp-devcontainer.${variant_name}.XXXXXX.json")
  TEMP_CONFIGS+=("$tmp_config")

  jq --arg image "$TOOLING_IMAGE_REF" '.image = $image' "$variant/.devcontainer/devcontainer.json" > "$tmp_config"

  populate_cache_args "variant-${variant_name}" VARIANT_CACHE_ARGS
  if [ "$USE_REGISTRY_CACHE_FROM" = "true" ]; then
    VARIANT_CACHE_ARGS+=(--cache-from "$REGISTRY/hakim-${variant_name}:latest")
  fi

  declare -a DEVCONTAINER_OUTPUT_ARGS=()
  if [ "$DIRECT_PUSH" = "true" ]; then
    DEVCONTAINER_OUTPUT_ARGS+=(--push true)
  fi

  devcontainer build \
    "${VARIANT_CACHE_ARGS[@]}" \
    "${DEVCONTAINER_OUTPUT_ARGS[@]}" \
    --workspace-folder devcontainers \
    --config "$tmp_config" \
    --image-name "$REGISTRY/hakim-$variant_name:latest" \
    --image-name "$REGISTRY/hakim-$variant_name:$RUN_REF" .

  rm -f "$tmp_config"
  add_image_tags "hakim-$variant_name"
done

if [ -n "$CUBE_VARIANTS" ]; then
  if [ "$CUBE_VARIANTS" = "all" ]; then
    CUBE_VARIANTS="$(printf '%s\n' "${VARIANT_PATHS[@]}" | xargs -n1 basename | paste -sd, -)"
  fi

  IFS=',' read -r -a CUBE_VARIANT_LIST <<<"$CUBE_VARIANTS"
  HAKIM_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

  for cube_variant in "${CUBE_VARIANT_LIST[@]}"; do
    cube_variant="$(echo "$cube_variant" | xargs)"
    [ -n "$cube_variant" ] || continue
    if [ ! -d "devcontainers/.devcontainer/images/$cube_variant" ]; then
      error "Unknown Cube variant: $cube_variant"
      exit 1
    fi
    cube_source_selected=false
    for selected_variant_path in "${VARIANT_PATHS[@]}"; do
      if [ "$(basename "$selected_variant_path")" = "$cube_variant" ]; then
        cube_source_selected=true
        break
      fi
    done
    if [ "$cube_source_selected" != "true" ]; then
      error "Cube variant '$cube_variant' must also be selected by --variants"
      exit 2
    fi
    if [ "$RUN_REF" = "latest" ]; then
      error "RUN_REF=latest is not allowed for Cube images; use an immutable ref"
      exit 1
    fi

    cube_image_ref="$REGISTRY/cube-hakim-${cube_variant}:$RUN_REF"
    if [ "$DIRECT_PUSH" = "true" ] || [ "$PUSH_IMAGES" = "true" ]; then
      if [ "${CUBE_ALLOW_TAG_OVERWRITE:-false}" != "true" ] && \
        docker buildx imagetools inspect "$cube_image_ref" >/dev/null 2>&1; then
        error "$cube_image_ref already exists; pick a new immutable RUN_REF"
        exit 1
      fi
    fi

    info "Building Cube Variant: $cube_variant..."

    declare -a CUBE_BUILD_ARGS=()
    CUBE_BUILD_ARGS+=(--build-arg "HAKIM_IMAGE=$REGISTRY/hakim-${cube_variant}:$RUN_REF")
    CUBE_BUILD_ARGS+=(--build-arg "HAKIM_VARIANT=$cube_variant")
    CUBE_BUILD_ARGS+=(--build-arg "HAKIM_COMMIT=$HAKIM_COMMIT")
    if [ -n "${CUBESANDBOX_BASE:-}" ]; then
      CUBE_BUILD_ARGS+=(--build-arg "CUBESANDBOX_BASE=$CUBESANDBOX_BASE")
    fi
    populate_cache_args "cube-${cube_variant}" CUBE_CACHE_ARGS

    docker buildx build \
      "${BUILDX_ARGS[@]}" \
      "${BUILD_OUTPUT_ARGS[@]}" \
      "${CUBE_CACHE_ARGS[@]}" \
      "${CUBE_BUILD_ARGS[@]}" \
      -t "$cube_image_ref" \
      devcontainers/cube
    BUILT_CUBE_IMAGE_TAGS+=("$cube_image_ref")
  done
fi

if [ "$PUSH_IMAGES" = true ] && [ "$DIRECT_PUSH" != "true" ]; then
  push_built_images
fi

info "Build Complete!"
