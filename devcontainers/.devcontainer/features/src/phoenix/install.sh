#!/bin/bash
set -e

VERSION=${VERSION:-"1.8.3"}
SEED_USER_HOME=${SEEDUSERHOME:-"true"}

echo "Activating feature 'phoenix'"

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

if ! command -v mix >/dev/null 2>&1; then
    echo "Error: Mix not found. The elixir feature must be installed before phoenix."
    exit 1
fi

echo "Installing OS dependencies for Phoenix file watching..."
apt-get update && apt-get install -y --no-install-recommends inotify-tools \
    && rm -rf /var/lib/apt/lists/*

if [ "$SEED_USER_HOME" = "true" ]; then
    _REMOTE_USER=${_REMOTE_USER:-"coder"}

    if [ "${_REMOTE_USER}" = "root" ]; then
        if id "coder" &>/dev/null; then
            _REMOTE_USER="coder"
        elif id "vscode" &>/dev/null; then
            _REMOTE_USER="vscode"
        fi
    fi

    USER_HOME=$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)
    if [ -n "$USER_HOME" ]; then
        mkdir -p "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"
        chown -R "${_REMOTE_USER}":"${_REMOTE_USER}" "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"

        if [ "$VERSION" = "latest" ]; then
            echo "Installing latest phx_new for ${_REMOTE_USER}..."
            su - "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" mix archive.install hex phx_new --force"
        else
            echo "Installing phx_new ${VERSION} for ${_REMOTE_USER}..."
            su - "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" mix archive.install hex phx_new ${VERSION} --force"
        fi

        echo "phx_new installed successfully"
    fi
fi

echo "Phoenix feature installation complete!"
echo "Users can install/update phx_new with: mix archive.install hex phx_new --force"
