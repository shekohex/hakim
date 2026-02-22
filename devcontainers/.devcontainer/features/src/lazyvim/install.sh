#!/bin/bash
set -euo pipefail

LAZYVIM_REPO="https://github.com/LazyVim/starter.git"
DEFAULT_PATH="/usr/local/share/mise/shims:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

if ! command -v git >/dev/null 2>&1; then
    echo "git is required to install LazyVim"
    exit 1
fi

if ! PATH="${DEFAULT_PATH}" command -v nvim >/dev/null 2>&1; then
    echo "nvim is required to install LazyVim"
    exit 1
fi

USER_HOME=$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)
if [ -z "${USER_HOME}" ]; then
    echo "could not resolve home directory for ${_REMOTE_USER}"
    exit 1
fi

NVIM_CONFIG_DIR="${USER_HOME}/.config/nvim"

mkdir -p "${USER_HOME}/.config"
mkdir -p "${USER_HOME}/.local/share/nvim" "${USER_HOME}/.local/state/nvim" "${USER_HOME}/.cache/nvim"
chown -R "${_REMOTE_USER}":"${_REMOTE_USER}" "${USER_HOME}/.config" "${USER_HOME}/.local" "${USER_HOME}/.cache"

if [ -d "${NVIM_CONFIG_DIR}" ]; then
    if [ -f "${NVIM_CONFIG_DIR}/lazy-lock.json" ] || [ -f "${NVIM_CONFIG_DIR}/lua/config/lazy.lua" ]; then
        echo "LazyVim config already exists at ${NVIM_CONFIG_DIR}, skipping..."
        exit 0
    fi
    rm -rf "${NVIM_CONFIG_DIR}"
fi

echo "Installing LazyVim for ${_REMOTE_USER}..."

su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} PATH=${DEFAULT_PATH} git clone --depth 1 ${LAZYVIM_REPO} ${NVIM_CONFIG_DIR}"
su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} rm -rf ${NVIM_CONFIG_DIR}/.git"

echo "LazyVim installed successfully."
