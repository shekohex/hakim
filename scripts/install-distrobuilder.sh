#!/bin/bash
#
# Install distrobuilder from source on Proxmox/Debian
# This avoids snap which isn't available on minimal Proxmox installs
#
set -euo pipefail

echo "Installing distrobuilder from source..."

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y \
    golang-go \
    gcc \
    debootstrap \
    rsync \
    gpg \
    squashfs-tools \
    git \
    make \
    build-essential \
    curl \
    xz-utils \
    libwin-hivex-perl \
    wimtools \
    genisoimage

# Check Go version (need 1.21+)
GO_VERSION=$(go version | grep -oP '\d+\.\d+' | head -1)
GO_MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)

if [ "$GO_MAJOR" -lt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 21 ]); then
    echo "Go version $GO_VERSION is too old. Need 1.21+"
    echo "Fetching latest Go version..."
    
    # Get latest stable Go version (use jq if available, otherwise grep)
    GO_JSON=$(curl -s "https://go.dev/dl/?mode=json")
    if command -v jq &> /dev/null; then
        GO_LATEST=$(echo "$GO_JSON" | jq -r '.[0].version' | sed 's/go//')
    else
        GO_LATEST=$(echo "$GO_JSON" | grep -o '"version": "go[^"]*"' | grep -o 'go[0-9.]*' | head -1 | sed 's/go//')
    fi
    if [ -z "$GO_LATEST" ]; then
        echo "Failed to fetch latest Go version, using fallback 1.26.0"
        GO_LATEST="1.26.0"
    fi
    
    echo "Installing Go $GO_LATEST..."
    curl -fsSL "https://go.dev/dl/go${GO_LATEST}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    ln -sf /usr/local/go/bin/go /usr/local/bin/go
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
    
    # Update PATH for this session
    export PATH="/usr/local/go/bin:$PATH"
fi

echo "Go version: $(go version)"

# Create directory for distrobuilder source
mkdir -p /opt/distrobuilder-src
cd /opt/distrobuilder-src

# Clone distrobuilder if not already present
if [ ! -d "distrobuilder/.git" ]; then
    echo "Cloning distrobuilder repository..."
    rm -rf distrobuilder
    git clone https://github.com/lxc/distrobuilder.git
fi

cd distrobuilder

# Get latest tag
git fetch --tags
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
echo "Building distrobuilder ${LATEST_TAG}..."

# Checkout latest stable
git checkout "${LATEST_TAG}"

# Build
echo "Compiling distrobuilder..."
# Build explicitly to avoid confusion with source directory
go build -v -o /tmp/distrobuilder-binary .

# Install to /usr/local/bin
mv /tmp/distrobuilder-binary /usr/local/bin/distrobuilder
chmod +x /usr/local/bin/distrobuilder

# Verify
echo ""
echo "Installation complete!"
echo "Version: $(distrobuilder --version)"
echo "Location: /usr/local/bin/distrobuilder"
