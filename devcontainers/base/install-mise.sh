#!/bin/bash
set -e
MISE_VERSION=${MISE_VERSION:-""}
MISE_SHA256_X64=${MISE_SHA256_X64:-""}
MISE_SHA256_ARM64=${MISE_SHA256_ARM64:-""}

if [ -z "$MISE_VERSION" ] || [ -z "$MISE_SHA256_X64" ] || [ -z "$MISE_SHA256_ARM64" ]; then
    echo "MISE_VERSION and checksums are required" >&2
    exit 1
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64)
        MISE_ARCH="x64"
        MISE_SHA256="$MISE_SHA256_X64"
        ;;
    arm64)
        MISE_ARCH="arm64"
        MISE_SHA256="$MISE_SHA256_ARM64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

MISE_TAR="/tmp/mise.tar.gz"
MISE_URL="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${MISE_ARCH}.tar.gz"
curl -fsSL "$MISE_URL" -o "$MISE_TAR"
echo "${MISE_SHA256}  ${MISE_TAR}" | sha256sum -c -
rm -rf /usr/local/lib/mise /usr/local/bin/mise
mkdir -p /usr/local/lib
tar -xzf "$MISE_TAR" -C /usr/local/lib
ln -s /usr/local/lib/mise/bin/mise /usr/local/bin/mise
rm -f "$MISE_TAR"

# Create global config dir
mkdir -p /etc/mise
cat << 'EOF' > /etc/mise/config.toml
[settings]
experimental = true
EOF

# Configure environment for mise shims without activate
cat << 'EO_PROFILE' > /etc/profile.d/mise.sh
export MISE_INSTALL_PATH=/usr/local/bin/mise
export MISE_DATA_DIR="${MISE_DATA_DIR:-/usr/local/share/mise}"
export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-/etc/mise}"
export MISE_GLOBAL_CONFIG_FILE="${MISE_GLOBAL_CONFIG_FILE:-/etc/mise/tools.toml}"
export PATH="$PATH:/usr/local/share/mise/shims"
EO_PROFILE
chmod +x /etc/profile.d/mise.sh
