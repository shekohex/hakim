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

VERSION=${VERSION:-"latest"}

echo "Installing Bun ${VERSION} via Mise for user ${_REMOTE_USER}..."

# Ensure we're using the global config
# export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1

# Install Bun
# Source mise profile to ensure we have shims in PATH
if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Bun via mise for user ${_REMOTE_USER}..."

# Install Bun
su - "${_REMOTE_USER}" -c "mise use --global bun@${VERSION}"

echo "Bun installed!"

echo "Verifying Bun installation..."
source /etc/profile.d/mise.sh
# Run verification as user
su - "${_REMOTE_USER}" -c "bun --version"
