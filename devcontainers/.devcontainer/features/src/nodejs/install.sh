#!/bin/bash
set -e


VERSION=${VERSION:-"24.13.0"}
NODE_GYP_VERSION=${NODE_GYP_VERSION:-${NODEGYPVERSION:-"12.2.0"}}

echo "Installing Node.js ${VERSION} via Mise..."

# Ensure we're using the global config
# export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

# Install Node.js
# Source mise profile to ensure we have shims in PATH
if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Node.js via mise..."

# Install Node.js
mise use --global node@${VERSION}

echo "Node.js installed!"

echo "Installing node-gyp for native module compilation..."
export NPM_CONFIG_CACHE=/tmp/.npm
npm install -g "node-gyp@${NODE_GYP_VERSION}"
rm -rf /tmp/.npm /root/.npm

echo "Verifying Node.js installation..."
source /etc/profile.d/mise.sh
# Run verification as user
node --version
