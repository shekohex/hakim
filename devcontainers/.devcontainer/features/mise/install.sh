#!/bin/bash
set -e

# TOOLS is passed as a comma-separated string because type: array options are joined by commas
if [ -z "${TOOLS}" ]; then
    echo "No tools specified to install."
    exit 0
fi

echo "Installing mise tools: ${TOOLS}"

# Ensure global config dir exists (it should be created by the base image or install-mise.sh)
mkdir -p /etc/mise

# We will append to /etc/mise/config.toml
# Configuring MISE_GLOBAL_CONFIG_FILE is safer to ensure commands use the right config
export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1 

# Ensure _REMOTE_USER is set
_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
    # Try to find a likely non-root user
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

# Update profile script to ensure shims are in PATH for the user
# We use $HOME in the export so it adapts to whoever sources it
cat << EOF > /etc/profile.d/mise.sh
export PATH="\$HOME/.local/share/mise/shims:\$PATH"
eval "\$(/usr/local/bin/mise activate bash --shims)"
EOF
chmod +x /etc/profile.d/mise.sh

# Split comma-separated string into array
IFS=',' read -ra TOOLS_ARRAY <<< "${TOOLS}"

for tool in "${TOOLS_ARRAY[@]}"; do
    # Trim whitespace just in case
    tool=$(echo "$tool" | xargs)
    if [ -n "$tool" ]; then
        echo "Adding $tool to user config for ${_REMOTE_USER}..."
        # execute as user to install in their home dir
        su - "${_REMOTE_USER}" -c "mise use --global $tool"
    fi
done

echo "Running mise install as ${_REMOTE_USER}..."
su - "${_REMOTE_USER}" -c "mise install"
