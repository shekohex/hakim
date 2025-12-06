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

info "Building Base Image..."
docker buildx build --load -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base

# Find variants
for variant in devcontainers/.devcontainer/images/*; do
    if [ -d "$variant" ]; then
        NAME=$(basename "$variant")
        info "Building Variant: $NAME..."
        
        # Use devcontainer CLI to build
        devcontainer build \
            --workspace-folder devcontainers \
            --config "$variant/.devcontainer/devcontainer.json" \
            --image-name "$REGISTRY/hakim-$NAME:latest" \
            --image-name "$REGISTRY/hakim-$NAME:$TIMESTAMP"
    fi
done

info "Build Complete!"
