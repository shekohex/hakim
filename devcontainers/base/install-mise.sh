#!/bin/bash
set -e
# Install mise to /usr/local/bin/mise
curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# Create global config dir
mkdir -p /etc/mise
cat << 'EOF' > /etc/mise/config.toml
[settings]
experimental = true
EOF

# Setup profile script for non-interactive sessions (IDEs, scripts, etc.)
# /etc/profile.d/ is sourced by login shells and many non-interactive contexts
cat << 'EO_PROFILE' > /etc/profile.d/mise.sh
export MISE_INSTALL_PATH=/usr/local/bin/mise
eval "$(/usr/local/bin/mise activate bash --shims)"
EO_PROFILE
chmod +x /etc/profile.d/mise.sh

# Setup for interactive sessions
# /etc/bash.bashrc is sourced by interactive non-login bash shells
cat << 'EO_BASHRC' >> /etc/bash.bashrc

# Mise activation for interactive shells
eval "$(/usr/local/bin/mise activate bash)"
EO_BASHRC
