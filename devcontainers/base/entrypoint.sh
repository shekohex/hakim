#!/bin/bash
set -euo pipefail

CODER_USER="${CODER_USER:-coder}"
CODER_UID="${CODER_UID:-1000}"
CODER_GID="${CODER_GID:-1001}"
CODER_HOME="${CODER_HOME:-/home/${CODER_USER}}"
PROJECT_DIR="${CODER_PROJECT_DIR:-${CODER_HOME}/project}"

export PATH="/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if ! getent group "${CODER_GID}" >/dev/null 2>&1; then
  groupadd --gid "${CODER_GID}" "${CODER_USER}"
fi

if ! id -u "${CODER_USER}" >/dev/null 2>&1; then
  useradd --uid "${CODER_UID}" --gid "${CODER_GID}" --home-dir "${CODER_HOME}" --create-home --shell /bin/bash "${CODER_USER}"
fi

mkdir -p "${CODER_HOME}" "${PROJECT_DIR}"
chown "${CODER_UID}:${CODER_GID}" "${CODER_HOME}" "${PROJECT_DIR}" || true

if [[ -n "${CODER_AGENT_BOOTSTRAP:-}" && ( -z "${CODER_AGENT_URL:-}" || -z "${CODER_AGENT_TOKEN:-}" ) ]]; then
  bootstrap_data="$(printf '%s' "${CODER_AGENT_BOOTSTRAP}" | base64 -d 2>/dev/null || true)"
  if [[ "${bootstrap_data}" == *"|"* ]]; then
    if [[ -z "${CODER_AGENT_URL:-}" ]]; then
      export CODER_AGENT_URL="${bootstrap_data%%|*}"
    fi
    if [[ -z "${CODER_AGENT_TOKEN:-}" ]]; then
      export CODER_AGENT_TOKEN="${bootstrap_data#*|}"
    fi
  fi
fi

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
