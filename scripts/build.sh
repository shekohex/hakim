#!/bin/bash
set -euo pipefail

# Registry prefix
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

# Build Cache Arguments
CACHE_ARGS=""
BASE_BUILD_CMD="docker build"
CODE_VERSION_ARG=""
OPENCODE_VERSION_ARG=""

# Parse named arguments
# Parse named arguments
function usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --code-version <version>      Specify the version of code-server to install (default: 4.106.3)
  --opencode-version <version>  Specify the version of opencode to install (default: latest)
  --help, -h                    Show this help message
EOF
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --code-version) CODE_VERSION_ARG="--build-arg CODE_SERVER_VERSION=$2"; shift ;;
        --opencode-version) OPENCODE_VERSION_ARG="--build-arg OPENCODE_VERSION=$2"; shift ;;
        --help|-h) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    info "Running in GitHub Actions, enabling caching and pushing..."
    # In CI, we use buildx with push to ensure the base image is available to the devcontainer builder (which runs in a separate context)
    # and to leverage GHA caching.
    CACHE_ARGS="--cache-from type=gha --cache-to type=gha,mode=max"
    BASE_BUILD_CMD="docker buildx build --push $CACHE_ARGS"
    # In CI, GITHUB_TOKEN is usually available automatically
fi

# Token Auto-detection
if [ -z "${GITHUB_TOKEN:-}" ]; then
    if command -v gh &> /dev/null; then
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

# Add secret to base build command if token is available
if [ -n "${GITHUB_TOKEN:-}" ]; then
    BASE_BUILD_CMD="$BASE_BUILD_CMD --secret id=github_token,env=GITHUB_TOKEN"
fi

info "Building Base Image..."
# Split the command to allow arguments to be processed correctly
# shellcheck disable=SC2086
$BASE_BUILD_CMD $CODE_VERSION_ARG $OPENCODE_VERSION_ARG -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base

# Find variants
for variant in devcontainers/.devcontainer/images/*; do
    # The original script had an 'if [ -d "$variant" ]' check.
    # The provided change removes this check and assumes all entries are directories.
    # If this assumption is incorrect, the script might fail on non-directory entries.
    variant_name=$(basename "$variant")
    info "Building Variant: $variant_name..."
    
    # Use devcontainer CLI to build with cache arguments
    # Note: devcontainer CLI might not support standard docker build-args easily for nested features, 
    # but base image args are handled above.
    devcontainer build $CACHE_ARGS \
        --workspace-folder devcontainers \
        --config "$variant/.devcontainer/devcontainer.json" \
        --image-name "$REGISTRY/hakim-$variant_name:latest" \
        --image-name "$REGISTRY/hakim-$variant_name:$TIMESTAMP" .
done

info "Build Complete!"
