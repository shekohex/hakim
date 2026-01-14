#!/bin/bash
set -euo pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
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
        if ! bun add -g @openchamber/web 2>&1 | tee "$LOG_FILE"; then
          echo "ERROR: OpenChamber install failed. See $LOG_FILE"
          exit 1
        fi
      else
        if ! bun add -g "@openchamber/web@${ARG_OPENCHAMBER_VERSION}" 2>&1 | tee "$LOG_FILE"; then
          echo "ERROR: OpenChamber install failed. See $LOG_FILE"
          exit 1
        fi
      fi
    fi

    GLOBAL_BIN_DIR=$(bun pm bin -g)
    if [ -n "$GLOBAL_BIN_DIR" ] && [ -f "$GLOBAL_BIN_DIR/openchamber" ]; then
      if command_exists sudo; then
        sudo ln -sf "$GLOBAL_BIN_DIR/openchamber" /usr/local/bin/openchamber
      fi
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
