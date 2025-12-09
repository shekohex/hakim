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

# Configure environment for mise shims without activate
cat << 'EO_PROFILE' > /etc/profile.d/mise.sh
export MISE_INSTALL_PATH=/usr/local/bin/mise
export MISE_DATA_DIR=/usr/local/share/mise
export MISE_CONFIG_DIR=/etc/mise
export PATH="/usr/local/share/mise/shims:$PATH"
EO_PROFILE
chmod +x /etc/profile.d/mise.sh
