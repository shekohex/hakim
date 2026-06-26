#!/bin/bash
set -euo pipefail

CODER_USER="${CODER_USER:-coder}"
CODER_UID="${CODER_UID:-}"
CODER_GID="${CODER_GID:-}"
CODER_HOME="${CODER_HOME:-/home/${CODER_USER}}"
PROJECT_DIR="${CODER_PROJECT_DIR:-${CODER_HOME}/project}"

export PATH="/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/share/mise/shims"
export MISE_INSTALL_PATH="/usr/local/bin/mise"
export LANG="${LANG:-C.UTF-8}"
export LANGUAGE="${LANGUAGE:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

DOCKER_DAEMON_PID=""
NIX_DAEMON_PID=""
DBUS_DAEMON_PID=""
AGENT_PID=""

bootstrap_nix_if_missing() {
  case "${BOOTSTRAP_NIX_IF_MISSING:-}" in
    1|true|TRUE|yes|YES) ;;
    *) return 0 ;;
  esac

  if [[ -x /nix/var/nix/profiles/default/bin/nix-daemon ]]; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "BOOTSTRAP_NIX_IF_MISSING is enabled but curl is missing" >&2
    return 1
  fi

  mkdir -p /nix
  curl -fsSL https://install.determinate.systems/nix | \
    sh -s -- install --no-confirm --diagnostic-endpoint "" \
      --extra-conf "experimental-features = nix-command flakes"
  ln -sf /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh /etc/profile.d/nix.sh
}

write_systemd_environment_file() {
  local env_file="/etc/hakim/agent.env"
  local entry name value escaped

  mkdir -p "$(dirname "${env_file}")"
  : > "${env_file}"
  chmod 0600 "${env_file}"
  while IFS= read -r -d '' entry; do
    name="${entry%%=*}"
    value="${entry#*=}"
    [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    escaped="${value//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\r'/\\r}"
    escaped="${escaped//$'\n'/\\n}"
    printf '%s="%s"\n' "${name}" "${escaped}" >> "${env_file}"
  done < <(env -0)
}

bootstrap_nix_if_missing

if [[ "$$" == "1" && -x /sbin/init ]]; then
  write_systemd_environment_file
  exec /sbin/init
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
    docker_data_root="${DOCKER_DATA_ROOT:-/var/lib/docker}"
    docker_log_file="${DOCKER_LOG_FILE:-/var/log/dockerd.log}"
    mkdir -p /var/run/docker "${docker_data_root}" /var/log
    mkdir -p "$(dirname "${docker_log_file}")"

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
      --data-root="${docker_data_root}" \
      --exec-root="${DOCKER_EXEC_ROOT:-/var/run/docker}" \
      --storage-driver="${DOCKER_STORAGE_DRIVER:-vfs}" \
      >"${docker_log_file}" 2>&1 &
    DOCKER_DAEMON_PID="$!"

    for _ in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi
fi

if [[ ! -d /run/systemd/system && ("${START_NIX_DAEMON:-1}" == "1" || "${START_NIX_DAEMON:-}" == "true") ]]; then
  if [[ -x /nix/var/nix/profiles/default/bin/nix-daemon ]] && [[ ! -S /nix/var/nix/daemon-socket/socket ]] && ! pgrep -x nix-daemon >/dev/null 2>&1; then
    mkdir -p /nix/var/nix/daemon-socket /var/log
    nohup /nix/var/nix/profiles/default/bin/nix-daemon >/var/log/nix-daemon.log 2>&1 &
    NIX_DAEMON_PID="$!"
  fi
fi

if [[ ! -d /run/systemd/system ]] && command -v dbus-daemon >/dev/null 2>&1 && [[ ! -S /run/dbus/system_bus_socket ]]; then
  mkdir -p /run/dbus /var/log
  nohup dbus-daemon --system --nofork >/var/log/dbus-system.log 2>&1 &
  DBUS_DAEMON_PID="$!"
fi

stop_docker_daemon() {
  if [[ -z "${DOCKER_DAEMON_PID}" ]]; then
    return 0
  fi

  if ! kill -0 "${DOCKER_DAEMON_PID}" >/dev/null 2>&1; then
    return 0
  fi

  kill -TERM "${DOCKER_DAEMON_PID}" >/dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    if ! kill -0 "${DOCKER_DAEMON_PID}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  kill -KILL "${DOCKER_DAEMON_PID}" >/dev/null 2>&1 || true
}

stop_nix_daemon() {
  if [[ -z "${NIX_DAEMON_PID}" ]]; then
    return 0
  fi

  if ! kill -0 "${NIX_DAEMON_PID}" >/dev/null 2>&1; then
    return 0
  fi

  kill -TERM "${NIX_DAEMON_PID}" >/dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    if ! kill -0 "${NIX_DAEMON_PID}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  kill -KILL "${NIX_DAEMON_PID}" >/dev/null 2>&1 || true
}

stop_dbus_daemon() {
  if [[ -z "${DBUS_DAEMON_PID}" ]]; then
    return 0
  fi

  if ! kill -0 "${DBUS_DAEMON_PID}" >/dev/null 2>&1; then
    return 0
  fi

  kill -TERM "${DBUS_DAEMON_PID}" >/dev/null 2>&1 || true
}

start_user_secret_service() {
  if ! command -v dbus-daemon >/dev/null 2>&1 || ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
    return 0
  fi

  local runtime_dir="/run/user/${CODER_UID}"
  mkdir -p "${runtime_dir}"
  chown "${CODER_UID}:${CODER_GID}" "${runtime_dir}"
  chmod 0700 "${runtime_dir}"

  local session_env
  session_env="$(su -s /bin/bash "${CODER_USER}" -c "XDG_RUNTIME_DIR='${runtime_dir}' dbus-launch --sh-syntax")" || return 0
  eval "${session_env}"
  export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID

  local keyring_env
  keyring_env="$(su -s /bin/bash "${CODER_USER}" -c "XDG_RUNTIME_DIR='${runtime_dir}' DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}' gnome-keyring-daemon --start --components=secrets,ssh")" || return 0
  eval "${keyring_env}"
  su -s /bin/bash "${CODER_USER}" -c "printf '' | XDG_RUNTIME_DIR='${runtime_dir}' DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}' gnome-keyring-daemon --unlock" >/dev/null 2>&1 || true
  export SSH_AUTH_SOCK GNOME_KEYRING_CONTROL
}

stop_agent() {
  if [[ -z "${AGENT_PID}" ]]; then
    return 0
  fi

  if ! kill -0 "${AGENT_PID}" >/dev/null 2>&1; then
    return 0
  fi

  pkill -TERM -P "${AGENT_PID}" >/dev/null 2>&1 || true
  kill -TERM "${AGENT_PID}" >/dev/null 2>&1 || true

  for _ in $(seq 1 30); do
    if ! kill -0 "${AGENT_PID}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  pkill -KILL -P "${AGENT_PID}" >/dev/null 2>&1 || true
  kill -KILL "${AGENT_PID}" >/dev/null 2>&1 || true
}

shutdown_services() {
  stop_agent
  stop_nix_daemon
  stop_dbus_daemon
  stop_docker_daemon
}

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
  start_user_secret_service

  export HOME="${CODER_HOME}"
  export USER="${CODER_USER}"
  export LOGNAME="${CODER_USER}"
  export CODER_PROJECT_DIR="${PROJECT_DIR}"
  export XDG_RUNTIME_DIR="/run/user/${CODER_UID}"

  su -s /bin/bash "${CODER_USER}" -c 'cd "$CODER_PROJECT_DIR" && exec env PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" GNOME_KEYRING_CONTROL="${GNOME_KEYRING_CONTROL:-}" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" coder agent' &
  AGENT_PID="$!"

  trap 'shutdown_services; exit 0' TERM INT HUP

  set +e
  wait "${AGENT_PID}"
  agent_exit_code=$?
  set -e

  AGENT_PID=""
  trap - TERM INT HUP
  stop_nix_daemon
  stop_dbus_daemon
  stop_docker_daemon

  exit "${agent_exit_code}"
fi

if [[ "$#" -gt 0 ]]; then
  exec "$@"
fi

exec su -s /bin/bash "${CODER_USER}"
