#!/bin/bash
set -e

VERSION=${VERSION:-"lts"}

echo "Installing Node.js ${VERSION} via Mise..."

# Ensure we're using the global config
export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1

# Install Node.js
mise use --global node@${VERSION}

echo "Node.js installed!"
