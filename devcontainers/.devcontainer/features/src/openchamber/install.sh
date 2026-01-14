#!/bin/bash
set -e

PACKAGE_NAME="@openchamber/web"

_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
  if id "coder" &>/dev/null; then
    _REMOTE_USER="coder"
  elif id "vscode" &>/dev/null; then
    _REMOTE_USER="vscode"
  fi
fi

if ! command -v bun >/dev/null 2>&1; then
  echo "bun is required to install OpenChamber"
  exit 1
fi

su - "${_REMOTE_USER}" -c "bun add -g ${PACKAGE_NAME}"

GLOBAL_BIN_DIR=$(su - "${_REMOTE_USER}" -c "bun pm bin -g")

if [ -n "${GLOBAL_BIN_DIR}" ] && [ -f "${GLOBAL_BIN_DIR}/openchamber" ]; then
  ln -sf "${GLOBAL_BIN_DIR}/openchamber" /usr/local/bin/openchamber
fi

openchamber --version
