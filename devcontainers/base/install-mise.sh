#!/bin/bash
set -e
# Install mise to /usr/local/bin/mise
curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# Create global config dir
mkdir -p /etc/mise
echo 'experimental = true' > /etc/mise/config.toml

# Setup profile script for all users
cat << 'EO_PROFILE' > /etc/profile.d/mise.sh
export MISE_INSTALL_PATH=/usr/local/bin/mise
eval "$(/usr/local/bin/mise activate bash)"
EO_PROFILE
chmod +x /etc/profile.d/mise.sh
