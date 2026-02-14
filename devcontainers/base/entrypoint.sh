#!/bin/bash
set -euo pipefail

CODER_USER="${CODER_USER:-coder}"
CODER_UID="${CODER_UID:-1000}"
CODER_GID="${CODER_GID:-1001}"
CODER_HOME="${CODER_HOME:-/home/${CODER_USER}}"
PROJECT_DIR="${CODER_PROJECT_DIR:-${CODER_HOME}/project}"

if ! getent group "${CODER_GID}" >/dev/null 2>&1; then
  groupadd --gid "${CODER_GID}" "${CODER_USER}"
fi

if ! id -u "${CODER_USER}" >/dev/null 2>&1; then
  useradd --uid "${CODER_UID}" --gid "${CODER_GID}" --home-dir "${CODER_HOME}" --create-home --shell /bin/bash "${CODER_USER}"
fi

mkdir -p "${CODER_HOME}" "${PROJECT_DIR}"
chown "${CODER_UID}:${CODER_GID}" "${CODER_HOME}" "${PROJECT_DIR}" || true

if [[ -n "${CODER_AGENT_URL:-}" && -n "${CODER_AGENT_TOKEN:-}" ]]; then
  export HOME="${CODER_HOME}"
  export USER="${CODER_USER}"
  export LOGNAME="${CODER_USER}"
  export CODER_PROJECT_DIR="${PROJECT_DIR}"
  exec su -s /bin/bash "${CODER_USER}" -c 'cd "$CODER_PROJECT_DIR" && exec coder agent'
fi

if [[ "$#" -gt 0 ]]; then
  exec "$@"
fi

exec su -s /bin/bash "${CODER_USER}"
