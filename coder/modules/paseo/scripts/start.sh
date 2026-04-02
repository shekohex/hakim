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

expand_home_path() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s\n' "$HOME/${1#~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

normalize_home_path() {
  local path="$1"

  path="$(expand_home_path "$path")"
  case "$path" in
    "$HOME/~")
      printf '%s\n' "$HOME"
      ;;
    "$HOME/~/"*)
      printf '%s\n' "$HOME/${path#"$HOME/~/"}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

ARG_PASEO_HOME_DIR=$(decode_b64 "${ARG_PASEO_HOME_DIR:-}")
ARG_PASEO_CONFIG=$(decode_b64 "${ARG_PASEO_CONFIG:-}")
ARG_PASEO_HOME_DIR=${ARG_PASEO_HOME_DIR:-~/.paseo}
ARG_PASEO_HOME_DIR="$(normalize_home_path "$ARG_PASEO_HOME_DIR")"

paseo_running() {
  paseo daemon status --json --home "$ARG_PASEO_HOME_DIR" 2> /dev/null | jq -e '.localDaemon == "running"' > /dev/null
}

write_paseo_config() {
  mkdir -p "$ARG_PASEO_HOME_DIR"

  if [ -n "$ARG_PASEO_CONFIG" ]; then
    printf '%s\n' "$ARG_PASEO_CONFIG" > "$ARG_PASEO_HOME_DIR/config.json"
    printf 'Wrote Paseo config to %s\n' "$ARG_PASEO_HOME_DIR/config.json"
  fi
}

start_paseo() {
  if paseo_running; then
    echo "Restarting Paseo daemon"
    paseo daemon restart --home "$ARG_PASEO_HOME_DIR" < /dev/null
    return
  fi

  echo "Starting Paseo daemon"
  paseo daemon start --home "$ARG_PASEO_HOME_DIR" < /dev/null
}

if ! command_exists paseo; then
  echo "ERROR: Paseo is not installed"
  exit 1
fi

write_paseo_config
start_paseo
paseo daemon status --json --home "$ARG_PASEO_HOME_DIR" || true
