#!/bin/bash
set -e

LAZYVIM_REPO="https://github.com/LazyVim/starter.git"

_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

USER_HOME=$(eval echo ~"${_REMOTE_USER}")
NVIM_CONFIG_DIR="${USER_HOME}/.config/nvim"

mkdir -p "${USER_HOME}/.config"
chown -R "${_REMOTE_USER}":"${_REMOTE_USER}" "${USER_HOME}/.config"

if [ -d "${NVIM_CONFIG_DIR}" ]; then
    echo "Neovim config already exists at ${NVIM_CONFIG_DIR}, skipping..."
    exit 0
fi

echo "Installing LazyVim for ${_REMOTE_USER}..."

su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin git clone --depth 1 ${LAZYVIM_REPO} ${NVIM_CONFIG_DIR}"
su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} rm -rf ${NVIM_CONFIG_DIR}/.git"

echo "LazyVim installed successfully."
