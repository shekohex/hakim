#!/bin/bash
set -e

ERLANG_VERSION=${ERLANG_VERSION:-${ERLANGVERSION:-"27"}}
ELIXIR_VERSION=${ELIXIR_VERSION:-${ELIXIRVERSION:-"1.17"}}
SEED_USER_HOME=${SEEDUSERHOME:-"true"}

echo "Activating feature 'elixir'"
echo "Installing Erlang ${ERLANG_VERSION} and Elixir ${ELIXIR_VERSION} via Mise..."

apt-get update && apt-get install -y --no-install-recommends \
    libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Erlang/OTP ${ERLANG_VERSION}..."
mise use --global erlang@${ERLANG_VERSION}

echo "Installing Elixir ${ELIXIR_VERSION}..."
mise use --global elixir@${ELIXIR_VERSION}

echo "Symlinking binaries to /usr/local/bin..."
for bin_path in $(mise bin-paths); do
    for bin_file in "$bin_path"/*; do
        if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
            ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"
        fi
    done
done

echo "Verifying installations..."
source /etc/profile.d/mise.sh
erl -version || true
elixir --version

if [ "$SEED_USER_HOME" = "true" ]; then
    echo "Seeding /etc/skel with Hex and Rebar for persistence..."
    
    # Create skeleton home directories
    mkdir -p /etc/skel/.mix
    mkdir -p /etc/skel/.hex
    mkdir -p /etc/skel/.cache
    
    # Set environment for skel operations
    export HOME=/etc/skel
    export MIX_HOME=/etc/skel/.mix
    export HEX_HOME=/etc/skel/.hex
    export MIX_ARCHIVES=/etc/skel/.mix/archives
    
    echo "Installing Hex package manager to /etc/skel..."
    mix local.hex --force
    
    echo "Installing Rebar build tool to /etc/skel..."
    mix local.rebar --force
    
    # Ensure proper permissions
    chmod -R 755 /etc/skel/.mix
    chmod -R 755 /etc/skel/.hex
    chmod -R 755 /etc/skel/.cache
    
    echo "Seeding complete. First boot will copy ~/.mix, ~/.hex to /home/coder."
fi

echo "Elixir feature installation complete!"
