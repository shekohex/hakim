#!/bin/bash
set -euo pipefail

REGISTRY="ghcr.io/shekohex"
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
OPENCODE_VERSION_ARG=""
CHROME_VERSION_ARG=""
FETCH_LATEST=false

function fetch_latest_version() {
  local repo="$1"
  gh release view --repo "$repo" --json tagName -q '.tagName' | sed 's/^v//'
}

function fetch_all_latest_versions() {
  info "Fetching latest tool versions..."
  LATEST_CODER=$(fetch_latest_version "coder/coder")
  LATEST_CODE_SERVER=$(fetch_latest_version "coder/code-server")
  LATEST_OPENCODE=$(fetch_latest_version "anomalyco/opencode")
  LATEST_CHROME=$(curl -sL "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages" 2>/dev/null | rg -A1 "^Package: google-chrome-stable" | rg "^Version:" | awk '{print $2}')
  info "Latest versions: coder=$LATEST_CODER, code-server=$LATEST_CODE_SERVER, opencode=$LATEST_OPENCODE, chrome=$LATEST_CHROME"
}

function usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --coder-version <version>     Specify the version of coder CLI to install
  --code-version <version>      Specify the version of code-server to install
  --opencode-version <version>  Specify the version of opencode to install
  --chrome-version <version>    Specify the version of Google Chrome to install
  --fetch-latest                Fetch and use latest versions for all tools (requires gh CLI)
  --help, -h                    Show this help message

If no version is specified, defaults from Dockerfile are used.
With --fetch-latest, all unspecified versions are resolved to latest.
EOF
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  --coder-version)
    CODER_VERSION_ARG="--build-arg CODER_VERSION=$2"
    shift
    ;;
  --code-version)
    CODE_VERSION_ARG="--build-arg CODE_SERVER_VERSION=$2"
    shift
    ;;
  --opencode-version)
    OPENCODE_VERSION_ARG="--build-arg OPENCODE_VERSION=$2"
    shift
    ;;
  --chrome-version)
    CHROME_VERSION_ARG="--build-arg GOOGLE_CHROME_VERSION=$2"
    shift
    ;;
  --fetch-latest) FETCH_LATEST=true ;;
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
  [ -z "$OPENCODE_VERSION_ARG" ] && OPENCODE_VERSION_ARG="--build-arg OPENCODE_VERSION=$LATEST_OPENCODE"
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

info "Building Base Image..."
# shellcheck disable=SC2086
$BASE_BUILD_CMD $CODER_VERSION_ARG $CODE_VERSION_ARG $OPENCODE_VERSION_ARG $CHROME_VERSION_ARG -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base

for variant in devcontainers/.devcontainer/images/*; do
  variant_name=$(basename "$variant")
  info "Building Variant: $variant_name..."

  devcontainer build $CACHE_ARGS \
    --workspace-folder devcontainers \
    --config "$variant/.devcontainer/devcontainer.json" \
    --image-name "$REGISTRY/hakim-$variant_name:latest" \
    --image-name "$REGISTRY/hakim-$variant_name:$TIMESTAMP" .
done

info "Build Complete!"
