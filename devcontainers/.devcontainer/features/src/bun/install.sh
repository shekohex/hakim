#!/bin/bash
set -e


VERSION=${VERSION:-"1.3.8"}

echo "Installing Bun ${VERSION} via Mise..."

# Ensure we're using the global config
# export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

# Install Bun
# Source mise profile to ensure we have shims in PATH
if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Bun via mise..."

# Install Bun
mise use --global bun@${VERSION}

echo "Bun installed!"

echo "Verifying Bun installation..."
source /etc/profile.d/mise.sh
# Run verification as user
bun --version
