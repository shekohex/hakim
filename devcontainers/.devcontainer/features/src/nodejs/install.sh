#!/bin/bash
set -e


VERSION=${VERSION:-"lts"}

echo "Installing Node.js ${VERSION} via Mise..."

# Ensure we're using the global config
# export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

# Install Node.js
# Source mise profile to ensure we have shims in PATH
if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

echo "Installing Node.js via mise..."

# Install Node.js
mise use --global node@${VERSION}

echo "Node.js installed!"

echo "Installing node-gyp for native module compilation..."
su - "${_REMOTE_USER:-coder}" -c "npm install -g node-gyp"

echo "Verifying Node.js installation..."
source /etc/profile.d/mise.sh
# Run verification as user
node --version

echo "Symlinking binaries to /usr/local/bin..."
for bin_path in $(mise bin-paths); do
    for bin_file in "$bin_path"/*; do
        if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
            ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"
        fi
    done
done
