#!/bin/bash
set -e

# TOOLS is passed as a comma-separated string because type: array options are joined by commas
if [ -z "${TOOLS}" ]; then
    echo "No tools specified to install."
    exit 0
fi

echo "Installing mise tools: ${TOOLS}"

export MISE_YES=1

# Ensure _REMOTE_USER is set
_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

USER_HOME=$(eval echo ~"${_REMOTE_USER}")
PROFILE_PATH="$USER_HOME/.profile"
if [ ! -f "$PROFILE_PATH" ]; then
    touch "$PROFILE_PATH"
    chown "${_REMOTE_USER}:${_REMOTE_USER}" "$PROFILE_PATH"
fi
if ! grep -q "mise/shims" "$PROFILE_PATH"; then
    echo 'export PATH="$HOME/.local/share/mise/shims:$PATH"' >> "$PROFILE_PATH"
fi

su - "${_REMOTE_USER}" -c "mkdir -p ~/.config/mise ~/.local/share/mise/shims"

# Split comma-separated string into array
IFS=',' read -ra TOOLS_ARRAY <<< "${TOOLS}"

for tool in "${TOOLS_ARRAY[@]}"; do
    tool=$(echo "$tool" | xargs)
    if [ -n "$tool" ]; then
        echo "Adding $tool to user config for ${_REMOTE_USER}..."
        su - "${_REMOTE_USER}" -c "MISE_YES=1 mise use --global $tool"
    fi
done

echo "Running mise install as ${_REMOTE_USER}..."
su - "${_REMOTE_USER}" -c "MISE_YES=1 mise install"
