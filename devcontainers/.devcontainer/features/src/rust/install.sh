#!/bin/bash
set -euo pipefail

VERSION=${VERSION:-"1.93.0"}
PROFILE=${PROFILE:-"minimal"}

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise
export RUSTUP_INIT_ARGS="--profile ${PROFILE}"

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

mise use --global "rust@${VERSION}"

rm -rf /root/.cache/mise

source /etc/profile.d/mise.sh
rustc --version
cargo --version
