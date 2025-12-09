#!/bin/bash
set -e


VERSION=${VERSION:-"latest"}

echo "Installing Bun ${VERSION} via Mise..."

# Ensure we're using the global config
# export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

# Install Bun
# Source mise profile to ensure we have shims in PATH
if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Bun via mise..."

# Install Bun
mise use --global bun@${VERSION}

echo "Bun installed!"

echo "Verifying Bun installation..."
source /etc/profile.d/mise.sh
# Run verification as user
bun --version

echo "Symlinking binaries to /usr/local/bin..."
for bin_path in $(mise bin-paths); do
    for bin_file in "$bin_path"/*; do
        if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
            ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"
        fi
    done
done
