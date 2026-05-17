#!/bin/bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

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
    "$HOME/.local/share/mise/installs/bun/*/bin/bun"; do
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

ARG_AUTH_JSON=$(echo -n "${ARG_AUTH_JSON:-}" | base64 -d 2> /dev/null || echo "")
ARG_INSTALL_SHEKOHEX_AGENT=${ARG_INSTALL_SHEKOHEX_AGENT:-true}
ARG_PRE_INSTALL_SCRIPT=$(echo -n "${ARG_PRE_INSTALL_SCRIPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_POST_INSTALL_SCRIPT=$(echo -n "${ARG_POST_INSTALL_SCRIPT:-}" | base64 -d 2> /dev/null || echo "")

run_pre_install_script() {
  if [ -n "$ARG_PRE_INSTALL_SCRIPT" ]; then
    echo "Running pre-install script..."
    echo -n "$ARG_PRE_INSTALL_SCRIPT" > /tmp/shekohex-agent-pre-install.sh
    chmod +x /tmp/shekohex-agent-pre-install.sh
    /tmp/shekohex-agent-pre-install.sh 2>&1 | tee /tmp/shekohex-agent-pre-install.log
  fi
}

setup_auth() {
  local auth_json_file="$HOME/.pi/agent/auth.json"

  mkdir -p "$(dirname "$auth_json_file")"

  if [ -n "$ARG_AUTH_JSON" ]; then
    echo "$ARG_AUTH_JSON" > "$auth_json_file"
    chmod 600 "$auth_json_file"
    printf 'added auth json to %s\n' "$auth_json_file"
  else
    printf 'auth json not provided\n'
  fi
}

install_shekohex_agent() {
  local bun_bin
  local pi_bin

  if [ "$ARG_INSTALL_SHEKOHEX_AGENT" != "true" ]; then
    echo "Shekohex Agent installation skipped (ARG_INSTALL_SHEKOHEX_AGENT=false)"
    return 0
  fi

  bun_bin="$(resolve_bun_bin 2> /dev/null || true)"
  if [ -z "$bun_bin" ]; then
    echo "ERROR: Bun is required to install Shekohex Agent"
    exit 1
  fi

  export PATH="$(dirname "$bun_bin"):$PATH"

  curl -fsSL https://github.com/shekohex/dotai/releases/download/preview/install-github-package.sh | bash -s -- --bun

  pi_bin="$HOME/.bun/bin/pi"
  if [ ! -f "$pi_bin" ]; then
    pi_bin="$(command -v pi 2> /dev/null || true)"
  fi

  if [ -n "$pi_bin" ] && [ -f "$pi_bin" ] && command_exists sudo; then
    sudo ln -sf "$pi_bin" /usr/local/bin/pi
  fi

  if ! command_exists pi; then
    echo "ERROR: Failed to install Shekohex Agent"
    exit 1
  fi

  pi --help > /dev/null
  echo "Shekohex Agent installed successfully"
}

run_post_install_script() {
  if [ -n "$ARG_POST_INSTALL_SCRIPT" ]; then
    echo "Running post-install script..."
    echo -n "$ARG_POST_INSTALL_SCRIPT" > /tmp/shekohex-agent-post-install.sh
    chmod +x /tmp/shekohex-agent-post-install.sh
    /tmp/shekohex-agent-post-install.sh 2>&1 | tee /tmp/shekohex-agent-post-install.log
  fi
}

run_pre_install_script
setup_auth
install_shekohex_agent
run_post_install_script
