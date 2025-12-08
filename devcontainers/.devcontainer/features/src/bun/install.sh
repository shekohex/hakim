#!/bin/bash
set -e

VERSION=${VERSION:-"latest"}

echo "Installing Bun ${VERSION} via Mise..."

# Ensure we're using the global config
export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1

# Install Bun
mise use --global bun@${VERSION}

echo "Bun installed!"

echo "Verifying Bun installation..."
source /etc/profile.d/mise.sh
bun --version
