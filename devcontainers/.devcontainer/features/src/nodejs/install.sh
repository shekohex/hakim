#!/bin/bash
set -e

_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
    # Try to find a likely non-root user
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

VERSION=${VERSION:-"lts"}

echo "Installing Node.js ${VERSION} via Mise for user ${_REMOTE_USER}..."

# Ensure we're using the global config
# export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1

# Install Node.js
# Source mise profile to ensure we have shims in PATH
if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Node.js via mise for user ${_REMOTE_USER}..."

# Install Node.js
su - "${_REMOTE_USER}" -c "mise use --global node@${VERSION}"

echo "Node.js installed!"

echo "Verifying Node.js installation..."
source /etc/profile.d/mise.sh
# Run verification as user
su - "${_REMOTE_USER}" -c "node --version"
