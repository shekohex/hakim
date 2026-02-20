#!/bin/bash
set -euo pipefail

ARG_ET_PORT=${ARG_ET_PORT:-2022}
ARG_SSH_PORT=${ARG_SSH_PORT:-2244}
ARG_BIND_IP=${ARG_BIND_IP:-127.0.0.1}
ARG_SSH_USER=${ARG_SSH_USER:-coder}

STATE_DIR="${HOME}/.local/share/hakim-et"
SSH_DIR="${HOME}/.ssh"
AUTHORIZED_KEYS_FILE="${SSH_DIR}/authorized_keys"

SSHD_CONFIG_FILE="${STATE_DIR}/sshd_config"
SSHD_HOST_KEY_FILE="${STATE_DIR}/ssh_host_ed25519_key"
SSHD_PID_FILE="${STATE_DIR}/sshd.pid"
SSHD_LOG_FILE="${STATE_DIR}/sshd.log"

ET_CONFIG_FILE="${STATE_DIR}/et.cfg"
ET_PID_FILE="${STATE_DIR}/etserver.pid"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  if ! command_exists "$1"; then
    printf "Missing required command: %s\n" "$1" >&2
    exit 1
  fi
}

pid_running() {
  local pid_file="$1"
  local pid

  if [ ! -f "$pid_file" ]; then
    return 1
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -z "$pid" ] || ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  kill -0 "$pid" >/dev/null 2>&1
}

stop_pid_file() {
  local pid_file="$1"
  local pid

  if ! pid_running "$pid_file"; then
    rm -f "$pid_file"
    return
  fi

  pid="$(cat "$pid_file")"
  kill "$pid" >/dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi

  rm -f "$pid_file"
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local timeout="$3"

  for _ in $(seq 1 "$timeout"); do
    if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

require_command etserver
require_command sshd
require_command ssh-keygen

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTHORIZED_KEYS_FILE"
chmod 600 "$AUTHORIZED_KEYS_FILE"

if [ ! -s "$AUTHORIZED_KEYS_FILE" ]; then
  printf "Warning: %s is empty; internal sshd may reject auth until a key is added.\n" "$AUTHORIZED_KEYS_FILE" >&2
fi

if [ ! -f "$SSHD_HOST_KEY_FILE" ]; then
  ssh-keygen -q -t ed25519 -N "" -f "$SSHD_HOST_KEY_FILE"
fi
chmod 600 "$SSHD_HOST_KEY_FILE"

cat >"$SSHD_CONFIG_FILE" <<EOF
Port ${ARG_SSH_PORT}
ListenAddress ${ARG_BIND_IP}
HostKey ${SSHD_HOST_KEY_FILE}
PidFile ${SSHD_PID_FILE}
AuthorizedKeysFile .ssh/authorized_keys
StrictModes no
AllowUsers ${ARG_SSH_USER}
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
AcceptEnv LANG LC_* LANGUAGE
UsePAM no
PermitRootLogin no
PermitTunnel yes
AllowTcpForwarding yes
GatewayPorts clientspecified
X11Forwarding no
PrintMotd no
PrintLastLog no
LogLevel VERBOSE
Subsystem sftp internal-sftp
EOF

if command_exists sudo; then
  sudo install -d -m 0755 /run/sshd >/dev/null 2>&1 || true
fi

stop_pid_file "$SSHD_PID_FILE"
stop_pid_file "$ET_PID_FILE"

SSHD_BIN="$(command -v sshd)"
"$SSHD_BIN" -f "$SSHD_CONFIG_FILE" -E "$SSHD_LOG_FILE"

if ! wait_for_tcp "$ARG_BIND_IP" "$ARG_SSH_PORT" 20; then
  printf "sshd did not start on %s:%s\n" "$ARG_BIND_IP" "$ARG_SSH_PORT" >&2
  exit 1
fi

cat >"$ET_CONFIG_FILE" <<EOF
[Networking]
port = ${ARG_ET_PORT}
bind_ip = ${ARG_BIND_IP}

[Debug]
verbose = 0
silent = 0
logsize = 20971520
telemetry = false
logdirectory = ${STATE_DIR}
EOF

ETSERVER_BIN="$(command -v etserver)"
"$ETSERVER_BIN" --cfgfile "$ET_CONFIG_FILE" --daemon --pidfile "$ET_PID_FILE"

if ! wait_for_tcp "$ARG_BIND_IP" "$ARG_ET_PORT" 20; then
  printf "etserver did not start on %s:%s\n" "$ARG_BIND_IP" "$ARG_ET_PORT" >&2
  exit 1
fi

printf "ET ready: etserver=%s:%s sshd=%s:%s\n" "$ARG_BIND_IP" "$ARG_ET_PORT" "$ARG_BIND_IP" "$ARG_SSH_PORT"
