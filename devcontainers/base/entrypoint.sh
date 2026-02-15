#!/bin/bash
set -euo pipefail

CODER_USER="${CODER_USER:-coder}"
CODER_UID="${CODER_UID:-}"
CODER_GID="${CODER_GID:-}"
CODER_HOME="${CODER_HOME:-/home/${CODER_USER}}"
PROJECT_DIR="${CODER_PROJECT_DIR:-${CODER_HOME}/project}"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${CODER_HOME}/.local/share/mise/shims:/usr/local/share/mise/shims"
export LANG="${LANG:-C.UTF-8}"
export LANGUAGE="${LANGUAGE:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
if [[ "${MISE_DATA_DIR:-}" == "/usr/local/share/mise" ]]; then
  export MISE_DATA_DIR="${CODER_HOME}/.local/share/mise"
fi
if [[ "${MISE_CONFIG_DIR:-}" == "/etc/mise" ]]; then
  export MISE_CONFIG_DIR="${CODER_HOME}/.config/mise"
fi

if id -u "${CODER_USER}" >/dev/null 2>&1; then
  CODER_UID="$(id -u "${CODER_USER}")"
  CODER_GID="$(id -g "${CODER_USER}")"
else
  CODER_UID="${CODER_UID:-1000}"
  CODER_GID="${CODER_GID:-1000}"

  if getent group "${CODER_GID}" >/dev/null 2>&1; then
    CODER_GROUP_NAME="$(getent group "${CODER_GID}" | cut -d: -f1)"
  elif getent group "${CODER_USER}" >/dev/null 2>&1; then
    CODER_GROUP_NAME="${CODER_USER}"
  else
    groupadd --gid "${CODER_GID}" "${CODER_USER}"
    CODER_GROUP_NAME="${CODER_USER}"
  fi

  useradd --uid "${CODER_UID}" --gid "${CODER_GROUP_NAME}" --home-dir "${CODER_HOME}" --create-home --shell /bin/bash "${CODER_USER}"
  CODER_GID="$(id -g "${CODER_USER}")"
fi

mkdir -p "${CODER_HOME}" "${PROJECT_DIR}" "${CODER_HOME}/.config/mise" "${CODER_HOME}/.local/share/mise"
chown "${CODER_UID}:${CODER_GID}" \
  "${CODER_HOME}" \
  "${PROJECT_DIR}" \
  "${CODER_HOME}/.config" \
  "${CODER_HOME}/.config/mise" \
  "${CODER_HOME}/.local" \
  "${CODER_HOME}/.local/share" \
  "${CODER_HOME}/.local/share/mise" || true
chown -R "${CODER_UID}:${CODER_GID}" "${CODER_HOME}/.config/mise" "${CODER_HOME}/.local/share/mise" || true

if [[ "${START_DOCKER_DAEMON:-1}" == "1" || "${START_DOCKER_DAEMON:-}" == "true" ]]; then
  if command -v dockerd >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
    mkdir -p /var/run/docker /var/lib/docker /var/log

    if [[ -S /var/run/docker.sock ]] && ! pgrep -x dockerd >/dev/null 2>&1; then
      rm -f /var/run/docker.sock
    fi

    if [[ -f /var/run/docker.pid ]]; then
      docker_pid="$(cat /var/run/docker.pid 2>/dev/null || true)"
      if [[ -z "${docker_pid}" || ! "${docker_pid}" =~ ^[0-9]+$ ]] || ! kill -0 "${docker_pid}" >/dev/null 2>&1; then
        rm -f /var/run/docker.pid
      fi
    fi

    if [[ -f /var/run/docker/containerd/containerd.pid ]]; then
      containerd_pid="$(cat /var/run/docker/containerd/containerd.pid 2>/dev/null || true)"
      containerd_alive=false
      if [[ -n "${containerd_pid}" && "${containerd_pid}" =~ ^[0-9]+$ ]] && kill -0 "${containerd_pid}" >/dev/null 2>&1; then
        if ps -p "${containerd_pid}" -o comm= 2>/dev/null | grep -qx "containerd"; then
          containerd_alive=true
        fi
      fi

      if [[ "${containerd_alive}" != "true" ]]; then
        rm -f /var/run/docker/containerd/containerd.pid \
          /var/run/docker/containerd/containerd.sock \
          /var/run/docker/containerd/containerd.sock.ttrpc \
          /var/run/docker/containerd/containerd-debug.sock
      fi
    fi

    nohup dockerd \
      --host=unix:///var/run/docker.sock \
      --data-root="${DOCKER_DATA_ROOT:-/var/lib/docker}" \
      --exec-root="${DOCKER_EXEC_ROOT:-/var/run/docker}" \
      --storage-driver="${DOCKER_STORAGE_DRIVER:-vfs}" \
      >"${DOCKER_LOG_FILE:-/var/log/dockerd.log}" 2>&1 &

    for _ in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi
fi

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
