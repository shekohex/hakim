#!/bin/bash
set -e

# Registry prefix
REGISTRY="ghcr.io/shekohex"
TIMESTAMP=$(date +%Y%m%d)

echo "Building Base Image..."
docker build -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base

# Find variants
for variant in devcontainers/variants/*; do
    if [ -d "$variant" ]; then
        NAME=$(basename "$variant")
        echo "Building Variant: $NAME..."
        
        # Use devcontainer CLI to build
        devcontainer build \
            --workspace-folder "$variant" \
            --image-name "$REGISTRY/hakim-$NAME:latest" \
            --image-name "$REGISTRY/hakim-$NAME:$TIMESTAMP"
    fi
done

echo "Build Complete!"
