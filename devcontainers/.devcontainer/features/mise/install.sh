#!/bin/bash
set -e

# TOOLS is passed as a comma-separated string because type: array options are joined by commas
if [ -z "${TOOLS}" ]; then
    echo "No tools specified to install."
    exit 0
fi

echo "Installing mise tools: ${TOOLS}"

export MISE_YES=1
MISE_BIN=${MISE_INSTALL_PATH:-/usr/local/bin/mise}

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
MISE_PATH_EXPORT='export PATH="$PATH:/usr/local/share/mise/shims:$HOME/.local/share/mise/shims"'

add_to_rc() {
    local file="$1"
    if [ ! -f "$file" ]; then
        touch "$file"
        chown "${_REMOTE_USER}:${_REMOTE_USER}" "$file"
    fi
    if ! grep -q "mise/shims" "$file"; then
        echo "$MISE_PATH_EXPORT" >> "$file"
    fi
}

add_to_rc "$USER_HOME/.profile"
add_to_rc "$USER_HOME/.bashrc"
if [ -f "$USER_HOME/.zshrc" ] || [ -f "/bin/zsh" ] || [ -f "/usr/bin/zsh" ]; then
   add_to_rc "$USER_HOME/.zshrc"
fi

su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} mkdir -p ~/.config/mise ~/.local/share/mise/shims"

# Split comma-separated string into array
IFS=',' read -ra TOOLS_ARRAY <<< "${TOOLS}"

for tool in "${TOOLS_ARRAY[@]}"; do
    tool=$(echo "$tool" | xargs)
    if [ -n "$tool" ]; then
        echo "Adding $tool to user config for ${_REMOTE_USER}..."
        su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} MISE_YES=1 MISE_INSTALL_PATH=${MISE_BIN} PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin ${MISE_BIN} use --global $tool"
    fi
done

echo "Running mise install as ${_REMOTE_USER}..."
su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} MISE_YES=1 MISE_INSTALL_PATH=${MISE_BIN} PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin ${MISE_BIN} install"
