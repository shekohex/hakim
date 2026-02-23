#!/bin/bash
set -euo pipefail

LAZYVIM_REPO="https://github.com/LazyVim/starter.git"
DEFAULT_PATH="/usr/local/share/mise/shims:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
SYSTEM_LAZYVIM_DIR="/opt/hakim/lazyvim/nvim"

if ! command -v git >/dev/null 2>&1; then
    echo "git is required to install LazyVim"
    exit 1
fi

if ! PATH="${DEFAULT_PATH}" command -v nvim >/dev/null 2>&1; then
    echo "nvim is required to install LazyVim"
    exit 1
fi

echo "Installing LazyVim seed into ${SYSTEM_LAZYVIM_DIR}..."

mkdir -p "$(dirname "${SYSTEM_LAZYVIM_DIR}")"
rm -rf "${SYSTEM_LAZYVIM_DIR}"
git clone --depth 1 "${LAZYVIM_REPO}" "${SYSTEM_LAZYVIM_DIR}"
rm -rf "${SYSTEM_LAZYVIM_DIR}/.git"
chmod -R a+rX "$(dirname "${SYSTEM_LAZYVIM_DIR}")"

echo "LazyVim seed installed successfully."
