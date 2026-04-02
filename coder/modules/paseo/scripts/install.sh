#!/bin/bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

decode_b64() {
  echo -n "$1" | base64 -d 2> /dev/null || echo ""
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

ARG_PASEO_VERSION=${ARG_PASEO_VERSION:-latest}
ARG_PASEO_TARBALL_URL=$(decode_b64 "${ARG_PASEO_TARBALL_URL:-}")
ARG_INSTALL_PASEO=${ARG_INSTALL_PASEO:-true}
ARG_PRE_INSTALL_SCRIPT=$(decode_b64 "${ARG_PRE_INSTALL_SCRIPT:-}")
ARG_POST_INSTALL_SCRIPT=$(decode_b64 "${ARG_POST_INSTALL_SCRIPT:-}")

run_pre_install_script() {
  if [ -n "$ARG_PRE_INSTALL_SCRIPT" ]; then
    echo "Running pre-install script..."
    echo -n "$ARG_PRE_INSTALL_SCRIPT" > /tmp/pre_install.sh
    chmod +x /tmp/pre_install.sh
    /tmp/pre_install.sh 2>&1 | tee /tmp/pre_install.log
  fi
}

install_paseo() {
  local bun_bin
  local package_spec
  local paseo_bin
  local installed_version
  local log_file

  if [ "$ARG_INSTALL_PASEO" != "true" ]; then
    echo "Paseo installation skipped (ARG_INSTALL_PASEO=false)"
    return 0
  fi

  bun_bin="$(resolve_bun_bin 2> /dev/null || true)"
  if [ -z "$bun_bin" ]; then
    echo "ERROR: Bun is required to install Paseo"
    exit 1
  fi
  export PATH="$(dirname "$bun_bin"):$PATH"

  installed_version="$(paseo --version 2> /dev/null || true)"
  if [ -n "$ARG_PASEO_TARBALL_URL" ]; then
    package_spec="@getpaseo/cli@${ARG_PASEO_TARBALL_URL}"
  else
    if [ "$ARG_PASEO_VERSION" = "latest" ]; then
      if [ -n "$installed_version" ]; then
        echo "Paseo already installed (${installed_version})"
        return 0
      fi
      package_spec="@getpaseo/cli"
    else
      if [ "$installed_version" = "$ARG_PASEO_VERSION" ]; then
        echo "Paseo already installed (${installed_version})"
        return 0
      fi
      package_spec="@getpaseo/cli@${ARG_PASEO_VERSION}"
    fi
  fi

  log_file="/tmp/paseo-install.log"
  if ! run_with_bun_lock "$bun_bin" add -g "$package_spec" 2>&1 | tee "$log_file"; then
    echo "ERROR: Paseo install failed. See $log_file"
    exit 1
  fi

  paseo_bin="$HOME/.bun/bin/paseo"
  if [ ! -f "$paseo_bin" ]; then
    paseo_bin="$(command -v paseo 2> /dev/null || true)"
  fi

  if [ -n "$paseo_bin" ] && [ -f "$paseo_bin" ] && command_exists sudo; then
    sudo ln -sf "$paseo_bin" /usr/local/bin/paseo
  fi

  if ! command_exists paseo; then
    echo "ERROR: Failed to install Paseo"
    exit 1
  fi

  echo "Paseo installed successfully"
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
install_paseo
run_post_install_script
