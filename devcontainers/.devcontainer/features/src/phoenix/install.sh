#!/bin/bash
set -euo pipefail

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
        MIX_TIMEOUT_CMD=""
        if command -v timeout >/dev/null 2>&1; then
            MIX_TIMEOUT_CMD="timeout 120"
        fi

        PHX_SEED_MARKER="/usr/local/share/mise/.seeded-phoenix-${_REMOTE_USER}-${VERSION}"
        if [ -f "$PHX_SEED_MARKER" ]; then
            echo "Phoenix seed already completed for ${_REMOTE_USER} (${VERSION}), skipping"
            echo "Phoenix feature installation complete!"
            exit 0
        fi

        mkdir -p "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"
        chown -R "${_REMOTE_USER}":"${_REMOTE_USER}" "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"

        if ls "${USER_HOME}/.mix/archives"/phx_new-*.ez >/dev/null 2>&1; then
            echo "phx_new archive already present for ${_REMOTE_USER}, skipping install"
            touch "$PHX_SEED_MARKER"
            echo "Phoenix feature installation complete!"
            exit 0
        fi

        if [ "$VERSION" = "latest" ]; then
            echo "Installing latest phx_new for ${_REMOTE_USER}..."
            phx_ok=false
            for attempt in 1 2; do
                if su -s /bin/bash "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" ${MIX_TIMEOUT_CMD} mix archive.install hex phx_new --force"; then
                    phx_ok=true
                    break
                fi
                echo "phx_new install attempt ${attempt} failed"
                sleep 3
            done
        else
            echo "Installing phx_new ${VERSION} for ${_REMOTE_USER}..."
            phx_ok=false
            for attempt in 1 2; do
                if su -s /bin/bash "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" ${MIX_TIMEOUT_CMD} mix archive.install hex phx_new ${VERSION} --force"; then
                    phx_ok=true
                    break
                fi
                echo "phx_new install attempt ${attempt} failed"
                sleep 3
            done
        fi

        if [ "$phx_ok" != "true" ]; then
            echo "Failed to seed phx_new for ${_REMOTE_USER}" >&2
            exit 1
        fi

        echo "phx_new installed successfully"
        touch "$PHX_SEED_MARKER"
    fi
fi

echo "Phoenix feature installation complete!"
echo "Users can install/update phx_new with: mix archive.install hex phx_new --force"
