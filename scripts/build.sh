#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/shekohex}"
CACHE_REPO="${CACHE_REPO:-}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
RUN_REF="${RUN_REF:-$TIMESTAMP}"

CODER_VERSION=""
CODE_SERVER_VERSION=""
CHROME_VERSION=""
FETCH_LATEST=false
PUSH_IMAGES=false

USE_REGISTRY_CACHE_FROM="${USE_REGISTRY_CACHE_FROM:-false}"
USE_REGISTRY_CACHE_TO="${USE_REGISTRY_CACHE_TO:-false}"

declare -a BASE_VERSION_ARGS=()
declare -a BUILT_IMAGE_TAGS=()
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
  --fetch-latest                 Fetch and use latest versions for all tools (requires gh CLI)
  --push                         Push built images after local build
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
  --fetch-latest) FETCH_LATEST=true ;;
  --push) PUSH_IMAGES=true ;;
  --help | -h) usage ;;
  *)
    echo "Unknown parameter passed: $1"
    usage
    ;;
  esac
  shift
done

if [ -z "$CACHE_REPO" ]; then
  CACHE_REPO="$REGISTRY/hakim-cache"
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

if [ "$PUSH_IMAGES" = true ]; then
  USE_REGISTRY_CACHE_TO=true
fi

if ! docker buildx version >/dev/null 2>&1; then
  error "docker buildx is required"
  exit 1
fi

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

declare -a BUILD_OUTPUT_ARGS=("--load")
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
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
}

BASE_IMAGE_REF="$REGISTRY/hakim-base:$RUN_REF"
TOOLING_IMAGE_REF="$REGISTRY/hakim-tooling:$RUN_REF"

info "Using run ref: $RUN_REF"
info "Using cache repo: $CACHE_REPO"
info "Registry cache import: $USE_REGISTRY_CACHE_FROM"
info "Registry cache export: $USE_REGISTRY_CACHE_TO"

populate_cache_args "base" BASE_CACHE_ARGS
info "Building Base Image..."
docker buildx build \
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
  "${BUILD_OUTPUT_ARGS[@]}" \
  "${SECRET_ARGS[@]}" \
  "${TOOLING_CACHE_ARGS[@]}" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE_REF" \
  -t "$REGISTRY/hakim-tooling:latest" \
  -t "$TOOLING_IMAGE_REF" \
  devcontainers/tooling
add_image_tags "hakim-tooling"

for variant in devcontainers/.devcontainer/images/*; do
  variant_name=$(basename "$variant")
  info "Building Variant: $variant_name..."

  tmp_config=$(mktemp "${variant}/.devcontainer/.tmp-devcontainer.${variant_name}.XXXXXX.json")
  TEMP_CONFIGS+=("$tmp_config")

  jq --arg image "$TOOLING_IMAGE_REF" '.image = $image' "$variant/.devcontainer/devcontainer.json" > "$tmp_config"

  populate_cache_args "variant-${variant_name}" VARIANT_CACHE_ARGS
  if [ "$USE_REGISTRY_CACHE_FROM" = "true" ]; then
    VARIANT_CACHE_ARGS+=(--cache-from "$REGISTRY/hakim-${variant_name}:latest")
  fi

  devcontainer build \
    "${VARIANT_CACHE_ARGS[@]}" \
    --workspace-folder devcontainers \
    --config "$tmp_config" \
    --image-name "$REGISTRY/hakim-$variant_name:latest" \
    --image-name "$REGISTRY/hakim-$variant_name:$RUN_REF" .

  rm -f "$tmp_config"
  add_image_tags "hakim-$variant_name"
done

if [ "$PUSH_IMAGES" = true ]; then
  push_built_images
fi

info "Build Complete!"
