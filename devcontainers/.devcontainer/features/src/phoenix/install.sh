#!/bin/bash
set -e

VERSION=${VERSION:-"latest"}
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
    echo "Installing Phoenix installer (phx_new) to /etc/skel for persistence..."

    mkdir -p /etc/skel/.mix
    mkdir -p /etc/skel/.hex
    mkdir -p /etc/skel/.cache

    export HOME=/etc/skel
    export MIX_HOME=/etc/skel/.mix
    export HEX_HOME=/etc/skel/.hex
    export MIX_ARCHIVES=/etc/skel/.mix/archives

    if [ "$VERSION" = "latest" ]; then
        echo "Installing latest phx_new..."
        mix archive.install hex phx_new --force
    else
        echo "Installing phx_new ${VERSION}..."
        mix archive.install hex phx_new ${VERSION} --force
    fi

    chmod -R 755 /etc/skel/.mix
    chmod -R 755 /etc/skel/.hex
    chmod -R 755 /etc/skel/.cache

    echo "phx_new installed successfully"
fi

echo "Phoenix feature installation complete!"
echo "Users can install/update phx_new with: mix archive.install hex phx_new --force"
