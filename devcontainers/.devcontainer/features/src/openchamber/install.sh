#!/bin/bash
set -e

PACKAGE_NAME="@openchamber/web"
VERSION=${VERSION:-"1.6.2"}

_REMOTE_USER=${_REMOTE_USER:-"coder"}

resolve_bun_bin() {
  for candidate in \
    /usr/local/share/mise/installs/bun/*/bin/bun \
    /root/.local/share/mise/installs/bun/*/bin/bun \
    /home/coder/.local/share/mise/installs/bun/*/bin/bun \
    /home/vscode/.local/share/mise/installs/bun/*/bin/bun \
    /home/${_REMOTE_USER}/.local/share/mise/installs/bun/*/bin/bun; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v bun >/dev/null 2>&1; then
    command -v bun
    return 0
  fi

  return 1
}

if [ "${_REMOTE_USER}" = "root" ]; then
  if id "coder" &>/dev/null; then
    _REMOTE_USER="coder"
  elif id "vscode" &>/dev/null; then
    _REMOTE_USER="vscode"
  fi
fi

BUN_BIN=$(resolve_bun_bin 2> /dev/null || true)
if [ -z "$BUN_BIN" ]; then
  echo "bun is required to install OpenChamber"
  exit 1
fi

USER_HOME=$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
  echo "could not resolve home directory for ${_REMOTE_USER}"
  exit 1
fi

su "${_REMOTE_USER}" -s /bin/bash -c "HOME=${USER_HOME} PATH=$(dirname "$BUN_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ${BUN_BIN} add -g ${PACKAGE_NAME}@${VERSION}"

GLOBAL_BIN_DIR="${USER_HOME}/.bun/bin"

if [ -n "${GLOBAL_BIN_DIR}" ] && [ -f "${GLOBAL_BIN_DIR}/openchamber" ]; then
  ln -sf "${GLOBAL_BIN_DIR}/openchamber" /usr/local/bin/openchamber
fi

openchamber --version
