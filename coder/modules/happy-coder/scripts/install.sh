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

ARG_HAPPY_CODER_VERSION=${ARG_HAPPY_CODER_VERSION:-0.15.0-beta.0}
ARG_INSTALL_HAPPY_CODER=${ARG_INSTALL_HAPPY_CODER:-true}
ARG_PRE_INSTALL_SCRIPT=$(echo -n "${ARG_PRE_INSTALL_SCRIPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_POST_INSTALL_SCRIPT=$(echo -n "${ARG_POST_INSTALL_SCRIPT:-}" | base64 -d 2> /dev/null || echo "")

run_pre_install_script() {
  if [ -n "$ARG_PRE_INSTALL_SCRIPT" ]; then
    echo "Running pre-install script..."
    echo -n "$ARG_PRE_INSTALL_SCRIPT" > /tmp/pre_install.sh
    chmod +x /tmp/pre_install.sh
    /tmp/pre_install.sh 2>&1 | tee /tmp/pre_install.log
  fi
}

install_happy_coder() {
  local bun_bin
  local package_spec
  local installed_version
  local happy_bin
  local happy_mcp_bin
  local log_file

  if [ "$ARG_INSTALL_HAPPY_CODER" != "true" ]; then
    echo "Happy installation skipped (ARG_INSTALL_HAPPY_CODER=false)"
    return 0
  fi

  bun_bin="$(resolve_bun_bin 2> /dev/null || true)"
  if [ -z "$bun_bin" ]; then
    echo "ERROR: Bun is required to install Happy"
    exit 1
  fi
  export PATH="$(dirname "$bun_bin"):$PATH"

  if [ "$ARG_HAPPY_CODER_VERSION" = "latest" ] || [ "$ARG_HAPPY_CODER_VERSION" = "stable" ]; then
    package_spec="happy-coder"
  else
    package_spec="happy-coder@${ARG_HAPPY_CODER_VERSION}"
  fi

  installed_version="$(happy daemon status 2>&1 | sed -n 's/^Happy CLI Version: //p' | head -n1 || true)"
  case "$ARG_HAPPY_CODER_VERSION" in
    latest|stable)
      if [ -n "$installed_version" ] && [[ "$installed_version" != *-beta.* ]]; then
        echo "Happy already installed (${installed_version})"
        return 0
      fi
      ;;
    beta)
      if [ -n "$installed_version" ] && [[ "$installed_version" == *-beta.* ]]; then
        echo "Happy already installed (${installed_version})"
        return 0
      fi
      ;;
    *)
      if [ "$installed_version" = "$ARG_HAPPY_CODER_VERSION" ]; then
        echo "Happy already installed (${installed_version})"
        return 0
      fi
      ;;
  esac

  log_file="/tmp/happy-coder-install.log"
  if ! run_with_bun_lock "$bun_bin" add -g "$package_spec" 2>&1 | tee "$log_file"; then
    echo "ERROR: Happy install failed. See $log_file"
    exit 1
  fi

  happy_bin="$HOME/.bun/bin/happy"
  happy_mcp_bin="$HOME/.bun/bin/happy-mcp"

  if [ ! -f "$happy_bin" ]; then
    happy_bin="$(command -v happy 2> /dev/null || true)"
  fi
  if [ ! -f "$happy_mcp_bin" ]; then
    happy_mcp_bin="$(command -v happy-mcp 2> /dev/null || true)"
  fi

  if [ -n "$happy_bin" ] && [ -f "$happy_bin" ] && command_exists sudo; then
    sudo ln -sf "$happy_bin" /usr/local/bin/happy
  fi
  if [ -n "$happy_mcp_bin" ] && [ -f "$happy_mcp_bin" ] && command_exists sudo; then
    sudo ln -sf "$happy_mcp_bin" /usr/local/bin/happy-mcp
  fi

  if ! command_exists happy; then
    echo "ERROR: Failed to install Happy"
    exit 1
  fi

  echo "Happy installed successfully"
}

run_post_install_script() {
  if [ -n "$ARG_POST_INSTALL_SCRIPT" ]; then
    echo "Running post-install script..."
    echo -n "$ARG_POST_INSTALL_SCRIPT" > /tmp/post_install.sh
    chmod +x /tmp/post_install.sh
    /tmp/post_install.sh 2>&1 | tee /tmp/post_install.log
  fi
}

run_pre_install_script
install_happy_coder
run_post_install_script
