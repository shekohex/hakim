#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/shekohex}"
TIMESTAMP=$(date +%Y%m%d)

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
  if [ $status -eq 0 ]; then
    info "Build completed successfully"
  else
    error "Build failed with exit code $status"
  fi
}

trap on_exit EXIT

CACHE_ARGS=""
BASE_BUILD_CMD="docker build"
CODER_VERSION_ARG=""
CODE_VERSION_ARG=""
CHROME_VERSION_ARG=""
FETCH_LATEST=false
PUSH_IMAGES=false

declare -a BUILT_IMAGE_TAGS=()

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
  --coder-version <version>     Specify the version of coder CLI to install
  --code-version <version>      Specify the version of code-server to install
  --chrome-version <version>    Specify the version of Google Chrome to install
  --fetch-latest                Fetch and use latest versions for all tools (requires gh CLI)
  --push                         Push built images after local build
  --help, -h                    Show this help message

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
  --coder-version)
    CODER_VERSION_ARG="--build-arg CODER_VERSION=$2"
    shift
    ;;
  --code-version)
    CODE_VERSION_ARG="--build-arg CODE_SERVER_VERSION=$2"
    shift
    ;;
  --chrome-version)
    CHROME_VERSION_ARG="--build-arg GOOGLE_CHROME_VERSION=$2"
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

if [ "$FETCH_LATEST" = true ]; then
  if ! command -v gh &>/dev/null; then
    error "gh CLI is required for --fetch-latest but not found"
    exit 1
  fi
  fetch_all_latest_versions
  [ -z "$CODER_VERSION_ARG" ] && CODER_VERSION_ARG="--build-arg CODER_VERSION=$LATEST_CODER"
  [ -z "$CODE_VERSION_ARG" ] && CODE_VERSION_ARG="--build-arg CODE_SERVER_VERSION=$LATEST_CODE_SERVER"
  [ -z "$CHROME_VERSION_ARG" ] && CHROME_VERSION_ARG="--build-arg GOOGLE_CHROME_VERSION=$LATEST_CHROME"
fi

if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  info "Running in GitHub Actions, enabling caching and pushing..."
  CACHE_ARGS="--cache-from type=gha --cache-to type=gha,mode=max"
  BASE_BUILD_CMD="docker buildx build --push $CACHE_ARGS"
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

if [ -n "${GITHUB_TOKEN:-}" ]; then
  BASE_BUILD_CMD="$BASE_BUILD_CMD --secret id=github_token,env=GITHUB_TOKEN"
fi

if [ "${GITHUB_ACTIONS:-false}" = "true" ] && [ "$PUSH_IMAGES" = true ]; then
  warn "Ignoring --push because GitHub Actions already pushes via buildx --push"
  PUSH_IMAGES=false
fi

function add_image_tags() {
  local image_name="$1"
  BUILT_IMAGE_TAGS+=("$REGISTRY/$image_name:latest")
  BUILT_IMAGE_TAGS+=("$REGISTRY/$image_name:$TIMESTAMP")
}

function push_built_images() {
  local image
  info "Pushing built images to $REGISTRY..."
  for image in "${BUILT_IMAGE_TAGS[@]}"; do
    info "Pushing $image"
    docker push "$image"
  done
}

info "Building Base Image..."
# shellcheck disable=SC2086
$BASE_BUILD_CMD $CODER_VERSION_ARG $CODE_VERSION_ARG $CHROME_VERSION_ARG -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base
add_image_tags "hakim-base"

info "Building Tooling Image..."
# shellcheck disable=SC2086
$BASE_BUILD_CMD --build-arg BASE_IMAGE="$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-tooling:latest" -t "$REGISTRY/hakim-tooling:$TIMESTAMP" devcontainers/tooling
add_image_tags "hakim-tooling"

for variant in devcontainers/.devcontainer/images/*; do
  variant_name=$(basename "$variant")
  info "Building Variant: $variant_name..."

  tmp_config="$variant/.devcontainer/.tmp-devcontainer.$$.$variant_name.json"
  jq --arg image "$REGISTRY/hakim-tooling:latest" '.image = $image' "$variant/.devcontainer/devcontainer.json" > "$tmp_config"

  devcontainer build $CACHE_ARGS \
    --workspace-folder devcontainers \
    --config "$tmp_config" \
    --image-name "$REGISTRY/hakim-$variant_name:latest" \
    --image-name "$REGISTRY/hakim-$variant_name:$TIMESTAMP" .

  rm -f "$tmp_config"

  add_image_tags "hakim-$variant_name"
done

if [ "$PUSH_IMAGES" = true ]; then
  push_built_images
fi

info "Build Complete!"
