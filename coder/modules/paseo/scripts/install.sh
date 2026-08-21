#!/bin/bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

ARG_ENABLED=${ARG_ENABLED:-true}

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

resolve_bun_bin() {
  if [ -x "$HOME/.bun/bin/bun" ]; then
    printf '%s\n' "$HOME/.bun/bin/bun"
    return 0
  fi

  for candidate in \
    /usr/local/share/mise/installs/bun/*/bin/bun \
    "$HOME/.local/share/mise/installs/bun/"*/bin/bun; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command_exists bun; then
    command -v bun
    return 0
  fi

  return 1
}

run_with_bun_lock() {
  if command_exists flock; then
    (
      exec 9>"/tmp/hakim-bun-global.lock"
      flock -w 600 9 || {
        echo "ERROR: timed out waiting for bun global lock"
        exit 1
      }
      "$@"
    )
    return
  fi

  local lock_dir="/tmp/hakim-bun-global.lock.d"
  local elapsed=0
  local timeout=600

  while ! mkdir "$lock_dir" 2> /dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "ERROR: timed out waiting for bun global lock"
      return 1
    fi
  done

  trap 'rmdir "$lock_dir" 2>/dev/null || true' RETURN
  "$@"
}

resolve_paseo_bin() {
  local candidate

  for candidate in \
    "$HOME/.bun/bin/paseo" \
    /usr/local/bin/paseo; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command_exists paseo; then
    command -v paseo
    return 0
  fi

  return 1
}

disable_paseo_service() {
  if ! command_exists sudo; then
    echo "ERROR: sudo is required to disable the Paseo systemd service"
    exit 1
  fi

  if ! command_exists systemctl; then
    echo "ERROR: systemd is required to disable Paseo"
    exit 1
  fi

  sudo systemctl disable --now paseo.service > /dev/null 2>&1 || true
  echo "Paseo disabled"
}

install_paseo() {
  local bun_bin

  bun_bin="$(resolve_bun_bin 2> /dev/null || true)"
  if [ -z "$bun_bin" ]; then
    echo "ERROR: Bun is required to install Paseo"
    exit 1
  fi

  export PATH="$(dirname "$bun_bin"):$PATH"
  run_with_bun_lock "$bun_bin" add -g @getpaseo/cli@latest
}

install_paseo_service() {
  local paseo_bin
  local service_user
  local service_group

  if ! command_exists sudo; then
    echo "ERROR: sudo is required to install the Paseo systemd service"
    exit 1
  fi

  if ! command_exists systemctl; then
    echo "ERROR: systemd is required to run Paseo"
    exit 1
  fi

  paseo_bin="$(resolve_paseo_bin 2> /dev/null || true)"
  if [ -z "$paseo_bin" ]; then
    echo "ERROR: Paseo is not installed"
    exit 1
  fi

  sudo ln -sf "$paseo_bin" /usr/local/bin/paseo
  service_user="$(id -un)"
  service_group="$(id -gn)"

  sudo systemctl stop paseo.service 2> /dev/null || true
  paseo daemon stop --home "$HOME/.paseo" > /dev/null 2>&1 || true

  sudo tee /etc/systemd/system/paseo.service > /dev/null <<EOF
[Unit]
Description=Paseo daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${service_user}
Group=${service_group}
WorkingDirectory=${HOME}
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/bin/paseo daemon start --foreground --home ${HOME}/.paseo --listen 127.0.0.1:6767 --no-relay --web-ui --hostnames true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable paseo.service > /dev/null
  sudo systemctl restart paseo.service

  sleep 1
  if ! sudo systemctl is-active --quiet paseo.service; then
    sudo systemctl status --no-pager paseo.service || true
    echo "ERROR: Paseo systemd service failed to start"
    exit 1
  fi

  paseo --help > /dev/null
  echo "Paseo installed and paseo.service started successfully"
}

if [ "$ARG_ENABLED" != "true" ]; then
  disable_paseo_service
  exit 0
fi

install_paseo
install_paseo_service
