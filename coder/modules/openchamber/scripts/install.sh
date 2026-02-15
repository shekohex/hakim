#!/bin/bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
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

ARG_OPENCHAMBER_VERSION=${ARG_OPENCHAMBER_VERSION:-latest}
ARG_INSTALL_OPENCHAMBER=${ARG_INSTALL_OPENCHAMBER:-true}
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

install_openchamber() {
  if [ "$ARG_INSTALL_OPENCHAMBER" = "true" ]; then
    if ! command_exists bun; then
      echo "ERROR: Bun is required to install OpenChamber"
      exit 1
    fi

    if ! command_exists openchamber; then
      LOG_FILE="/tmp/openchamber-install.log"
      if [ "$ARG_OPENCHAMBER_VERSION" = "latest" ]; then
        if ! run_with_bun_lock bun add -g @openchamber/web 2>&1 | tee "$LOG_FILE"; then
          echo "ERROR: OpenChamber install failed. See $LOG_FILE"
          exit 1
        fi
      else
        if ! run_with_bun_lock bun add -g "@openchamber/web@${ARG_OPENCHAMBER_VERSION}" 2>&1 | tee "$LOG_FILE"; then
          echo "ERROR: OpenChamber install failed. See $LOG_FILE"
          exit 1
        fi
      fi
    fi

    OPENCHAMBER_BIN=$(command -v openchamber 2> /dev/null || true)
    if [ -n "$OPENCHAMBER_BIN" ] && [ -f "$OPENCHAMBER_BIN" ] && command_exists sudo; then
      sudo ln -sf "$OPENCHAMBER_BIN" /usr/local/bin/openchamber
    fi
  fi
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
install_openchamber
run_post_install_script
