#!/bin/bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

ARG_ENABLED=${ARG_ENABLED:-true}
ARG_UPDATE_SCRIPT=${ARG_UPDATE_SCRIPT:-}

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

resolve_t3_bin() {
  local candidate

  for candidate in \
    "$HOME/.bun/bin/t3" \
    /usr/local/bin/t3; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command_exists t3; then
    command -v t3
    return 0
  fi

  return 1
}

disable_t3code_service() {
  if ! command_exists sudo; then
    echo "ERROR: sudo is required to disable the T3 Code systemd service"
    exit 1
  fi

  if ! command_exists systemctl; then
    echo "ERROR: systemd is required to disable T3 Code"
    exit 1
  fi

  sudo systemctl disable --now t3code.service > /dev/null 2>&1 || true
  echo "T3 Code disabled"
}

install_t3code() {
  local bun_bin

  bun_bin="$(resolve_bun_bin 2> /dev/null || true)"
  if [ -z "$bun_bin" ]; then
    echo "ERROR: Bun is required to install T3 Code"
    exit 1
  fi

  export PATH="$(dirname "$bun_bin"):$PATH"

  curl -fsSL https://github.com/shekohex/t3code/releases/download/fork-preview/install-github-package.sh | bash -s -- --bun
}

install_t3code_service() {
  local t3_bin
  local service_user
  local service_group

  if ! command_exists sudo; then
    echo "ERROR: sudo is required to install the T3 Code systemd service"
    exit 1
  fi

  if ! command_exists systemctl; then
    echo "ERROR: systemd is required to run T3 Code"
    exit 1
  fi

  if [ ! -f "$ARG_UPDATE_SCRIPT" ]; then
    echo "ERROR: T3 Code update script is missing"
    exit 1
  fi

  t3_bin="$(resolve_t3_bin 2> /dev/null || true)"
  if [ -z "$t3_bin" ]; then
    echo "ERROR: T3 Code is not installed"
    exit 1
  fi

  sudo ln -sf "$t3_bin" /usr/local/bin/t3
  sudo install -m 0755 "$ARG_UPDATE_SCRIPT" /usr/local/bin/t3-update
  service_user="$(id -un)"
  service_group="$(id -gn)"

  sudo tee /etc/systemd/system/t3code.service > /dev/null <<EOF
[Unit]
Description=T3 Code server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${service_user}
Group=${service_group}
WorkingDirectory=${HOME}
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/bin/t3 serve --host 0.0.0.0 --port 1337
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable t3code.service > /dev/null
  sudo systemctl restart t3code.service

  sleep 1
  if ! sudo systemctl is-active --quiet t3code.service; then
    sudo systemctl status --no-pager t3code.service || true
    echo "ERROR: T3 Code systemd service failed to start"
    exit 1
  fi

  t3 --help > /dev/null
  echo "T3 Code installed and t3code.service started successfully"
}

if [ "$ARG_ENABLED" != "true" ]; then
  disable_t3code_service
  exit 0
fi

install_t3code
install_t3code_service
