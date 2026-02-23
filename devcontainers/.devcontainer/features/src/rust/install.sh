#!/bin/bash
set -euo pipefail

VERSION=${VERSION:-"1.93.0"}
PROFILE=${PROFILE:-"minimal"}

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise
export RUSTUP_INIT_ARGS="--profile ${PROFILE}"
export CARGO_HOME=/usr/local/cargo
export RUSTUP_HOME=/usr/local/rustup

mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

mise use --global "rust@${VERSION}"

for bin in rustc cargo rustup rustfmt cargo-fmt cargo-clippy clippy-driver; do
    if [ -x "$CARGO_HOME/bin/$bin" ]; then
        ln -sf "$CARGO_HOME/bin/$bin" "/usr/local/bin/$bin"
    fi
done

chmod -R a+rX "$CARGO_HOME" "$RUSTUP_HOME"

rm -rf /root/.cache/mise

/usr/local/bin/rustc --version
/usr/local/bin/cargo --version
