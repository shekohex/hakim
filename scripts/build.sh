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

if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    info "Running in GitHub Actions, enabling caching and pushing..."
    # In CI, we use buildx with push to ensure the base image is available to the devcontainer builder (which runs in a separate context)
    # and to leverage GHA caching.
    CACHE_ARGS="--cache-from type=gha --cache-to type=gha,mode=max"
    BASE_BUILD_CMD="docker buildx build --push $CACHE_ARGS"
fi

info "Building Base Image..."
# Split the command to allow arguments to be processed correctly
$BASE_BUILD_CMD -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base

# Find variants
for variant in devcontainers/.devcontainer/images/*; do
    # The original script had an 'if [ -d "$variant" ]' check.
    # The provided change removes this check and assumes all entries are directories.
    # If this assumption is incorrect, the script might fail on non-directory entries.
    variant_name=$(basename "$variant")
    info "Building Variant: $variant_name..."
    
    # Use devcontainer CLI to build with cache arguments
    devcontainer build $CACHE_ARGS \
        --workspace-folder devcontainers \
        --config "$variant/.devcontainer/devcontainer.json" \
        --image-name "$REGISTRY/hakim-$variant_name:latest" \
        --image-name "$REGISTRY/hakim-$variant_name:$TIMESTAMP" .
done

info "Build Complete!"
