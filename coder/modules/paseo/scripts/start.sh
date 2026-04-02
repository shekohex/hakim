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

wait_for_paseo() {
  local timeout=30
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if paseo_running; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

print_paseo_status() {
  local status_json
  local listen
  local version
  local provider_summary

  status_json="$(paseo daemon status --json --home "$ARG_PASEO_HOME_DIR" 2> /dev/null || true)"
  if [ -z "$status_json" ] || ! printf '%s' "$status_json" | jq -e '.localDaemon == "running"' > /dev/null 2>&1; then
    return 1
  fi

  listen="$(printf '%s' "$status_json" | jq -r '.listen // "unknown"')"
  version="$(printf '%s' "$status_json" | jq -r '.cliVersion // "unknown"')"
  provider_summary="$(printf '%s' "$status_json" | jq -r '[.providers[]? | select(.path != null) | .label] | if length > 0 then join(", ") else "none" end')"

  printf 'Paseo daemon ready on %s\n' "$listen"
  printf 'Paseo CLI version: %s\n' "$version"
  printf 'Available providers: %s\n' "$provider_summary"
  printf 'Paseo logs: %s\n' "$ARG_PASEO_HOME_DIR/daemon.log"
}

write_paseo_config() {
  mkdir -p "$ARG_PASEO_HOME_DIR"

  if [ -n "$ARG_PASEO_CONFIG" ]; then
    printf '%s\n' "$ARG_PASEO_CONFIG" > "$ARG_PASEO_HOME_DIR/config.json"
    printf 'Wrote Paseo config to %s\n' "$ARG_PASEO_HOME_DIR/config.json"
  fi
}

start_paseo() {
  local log_file="/tmp/paseo-daemon-start.log"
  local start_exit_code=0

  if paseo_running; then
    echo "Restarting Paseo daemon"
    paseo daemon restart --home "$ARG_PASEO_HOME_DIR" > "$log_file" 2>&1 < /dev/null || start_exit_code=$?
    if ! wait_for_paseo; then
      if [ -s "$log_file" ]; then
        cat "$log_file"
      fi
      if [ "$start_exit_code" -ne 0 ]; then
        echo "ERROR: Paseo daemon restart exited with code $start_exit_code"
      fi
      echo "ERROR: Paseo daemon did not become ready after restart"
      return 1
    fi
    print_paseo_status
    return
  fi

  echo "Starting Paseo daemon"
  paseo daemon start --home "$ARG_PASEO_HOME_DIR" > "$log_file" 2>&1 < /dev/null || start_exit_code=$?
  if ! wait_for_paseo; then
    if [ -s "$log_file" ]; then
      cat "$log_file"
    fi
    if [ "$start_exit_code" -ne 0 ]; then
      echo "ERROR: Paseo daemon start exited with code $start_exit_code"
    fi
    echo "ERROR: Paseo daemon did not become ready"
    return 1
  fi
  print_paseo_status
}

if ! command_exists paseo; then
  echo "ERROR: Paseo is not installed"
  exit 1
fi

write_paseo_config
start_paseo
