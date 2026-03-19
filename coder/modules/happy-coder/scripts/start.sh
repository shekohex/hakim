#!/bin/bash
set -euo pipefail

export MIX_HOME=/home/coder/.mix
export HEX_HOME=/home/coder/.hex
export MIX_ARCHIVES=/home/coder/.mix/archives
export MISE_INSTALL_PATH=/usr/local/bin/mise
export MISE_DATA_DIR=/usr/local/share/mise
export MISE_CONFIG_DIR=/etc/mise
export MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

decode_b64() {
  echo -n "$1" | base64 -d 2> /dev/null || true
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_OPENCODE_PORT=${ARG_OPENCODE_PORT:-4096}
ARG_HAPPY_HOME_DIR=$(decode_b64 "${ARG_HAPPY_HOME_DIR:-}")
ARG_MANAGER_SCRIPT=${ARG_MANAGER_SCRIPT:-}

install_manager() {
  local target_dir="$HOME/.local/bin"
  local target_file="$target_dir/happy-opencode"
  local bun_target_dir="$HOME/.bun/bin"

  if [ -z "$ARG_MANAGER_SCRIPT" ] || [ ! -f "$ARG_MANAGER_SCRIPT" ]; then
    echo 'ERROR: Happy manager script not found'
    exit 1
  fi

  mkdir -p "$target_dir"
  mkdir -p "$bun_target_dir"

  {
    printf '#!/bin/bash\n'
    printf 'export HAPPY_OPENCODE_PORT_DEFAULT=%q\n' "$ARG_OPENCODE_PORT"
    printf 'export HAPPY_OPENCODE_HOME_DEFAULT=%q\n' "${ARG_HAPPY_HOME_DIR:-~/.happy}"
    sed '1d' "$ARG_MANAGER_SCRIPT"
  } > "$target_file"

  chmod +x "$target_file"
  ln -sf "$target_file" "$bun_target_dir/happy-opencode"

  if command_exists sudo; then
    sudo ln -sf "$target_file" /usr/local/bin/happy-opencode
  fi

  printf 'Happy CLI manager installed: %s\n' "$target_file"
  printf 'Start a session in the current directory with: happy-opencode start\n'
  printf 'Show daemon sessions with: happy-opencode list\n'
}

if ! command_exists happy; then
  echo 'ERROR: Happy is not installed'
  exit 1
fi

install_manager
