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

expand_home() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${1#~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_OPENCODE_PORT=${ARG_OPENCODE_PORT:-4096}
ARG_HAPPY_SERVER_URL=$(decode_b64 "${ARG_HAPPY_SERVER_URL:-}")
ARG_HAPPY_WEBAPP_URL=$(decode_b64 "${ARG_HAPPY_WEBAPP_URL:-}")
ARG_HAPPY_HOME_DIR=$(decode_b64 "${ARG_HAPPY_HOME_DIR:-}")
ARG_HAPPY_DISABLE_CAFFEINATE=${ARG_HAPPY_DISABLE_CAFFEINATE:-false}
ARG_HAPPY_EXPERIMENTAL=${ARG_HAPPY_EXPERIMENTAL:-false}

ARG_HAPPY_SERVER_URL=${ARG_HAPPY_SERVER_URL:-https://api.cluster-fluster.com}
ARG_HAPPY_WEBAPP_URL=${ARG_HAPPY_WEBAPP_URL:-https://app.happy.engineering}
ARG_HAPPY_HOME_DIR=${ARG_HAPPY_HOME_DIR:-"~/.happy"}

set_happy_env() {
  export HAPPY_SERVER_URL="$ARG_HAPPY_SERVER_URL"
  export HAPPY_WEBAPP_URL="$ARG_HAPPY_WEBAPP_URL"
  export HAPPY_HOME_DIR="$(expand_home "$ARG_HAPPY_HOME_DIR")"

  unset HAPPY_DISABLE_CAFFEINATE HAPPY_EXPERIMENTAL || true
  if is_true "$ARG_HAPPY_DISABLE_CAFFEINATE"; then
    export HAPPY_DISABLE_CAFFEINATE=true
  fi
  if is_true "$ARG_HAPPY_EXPERIMENTAL"; then
    export HAPPY_EXPERIMENTAL=true
  fi
}

happy_credentials_file() {
  printf '%s/access.key\n' "$HAPPY_HOME_DIR"
}

happy_configured() {
  [ -f "$(happy_credentials_file)" ]
}

opencode_url() {
  printf 'http://localhost:%s\n' "$ARG_OPENCODE_PORT"
}

opencode_healthcheck() {
  curl -fsS "$(opencode_url)/global/health" > /dev/null 2>&1
}

acquire_supervisor_lock() {
  local lock_file="/tmp/happy-coder-supervisor-${ARG_OPENCODE_PORT}.lock"

  if command_exists flock; then
    exec 9>"$lock_file"
    if ! flock -n 9; then
      printf 'Happy supervisor is already running for OpenCode port %s\n' "$ARG_OPENCODE_PORT"
      return 1
    fi
    return 0
  fi

  local lock_dir="${lock_file}.d"
  if ! mkdir "$lock_dir" 2> /dev/null; then
    printf 'Happy supervisor is already running for OpenCode port %s\n' "$ARG_OPENCODE_PORT"
    return 1
  fi

  trap "rmdir '$lock_dir' 2> /dev/null || true" EXIT
  return 0
}

ensure_happy_daemon() {
  if command_exists timeout; then
    timeout 30 happy daemon start >> /tmp/happy-coder-daemon.log 2>&1 || true
  else
    happy daemon start >> /tmp/happy-coder-daemon.log 2>&1 || true
  fi
}

run_supervisor() {
  local backoff=1
  local max_backoff=30
  local health_failures=0
  local max_health_failures=3
  local auth_wait_logged=false
  local opencode_wait_logged=false

  if ! acquire_supervisor_lock; then
    return 0
  fi

  printf 'Happy supervisor started for OpenCode port %s\n' "$ARG_OPENCODE_PORT"

  while true; do
    set_happy_env
    mkdir -p "$HAPPY_HOME_DIR"

    if ! happy_configured; then
      if [ "$auth_wait_logged" = false ]; then
        printf "Happy auth not found at %s. Run 'happy auth' in the workspace and the supervisor will reconnect automatically.\n" "$(happy_credentials_file)"
        auth_wait_logged=true
      fi
      sleep 15
      continue
    fi
    auth_wait_logged=false

    if ! opencode_healthcheck; then
      if [ "$opencode_wait_logged" = false ]; then
        printf 'Waiting for OpenCode server at %s\n' "$(opencode_url)"
        opencode_wait_logged=true
      fi
      sleep 5
      continue
    fi
    opencode_wait_logged=false

    if ! cd "$ARG_WORKDIR"; then
      printf 'ERROR: failed to enter workdir %s\n' "$ARG_WORKDIR"
      sleep "$backoff"
      backoff=$((backoff * 2))
      if [ "$backoff" -gt "$max_backoff" ]; then
        backoff=$max_backoff
      fi
      continue
    fi

    ensure_happy_daemon

    printf 'Running: happy acp opencode --attach %s --cwd %s --started-by daemon\n' "$(opencode_url)" "$ARG_WORKDIR"
    happy acp opencode --attach "$(opencode_url)" --cwd "$ARG_WORKDIR" --started-by daemon >> /tmp/happy-coder-session.log 2>&1 &
    local happy_pid=$!
    backoff=1
    health_failures=0

    while kill -0 "$happy_pid" 2> /dev/null; do
      if opencode_healthcheck; then
        health_failures=0
      else
        health_failures=$((health_failures + 1))
        if [ "$health_failures" -ge "$max_health_failures" ]; then
          printf 'OpenCode healthcheck failed %s times, restarting Happy ACP session\n' "$health_failures"
          kill "$happy_pid" 2> /dev/null || true
          sleep 1
          kill -9 "$happy_pid" 2> /dev/null || true
          break
        fi
      fi
      sleep 5
    done

    wait "$happy_pid" 2> /dev/null || true

    printf 'Happy ACP session exited, restarting in %s seconds\n' "$backoff"
    sleep "$backoff"
    backoff=$((backoff * 2))
    if [ "$backoff" -gt "$max_backoff" ]; then
      backoff=$max_backoff
    fi
  done
}

start_happy_supervisor() {
  printf 'Starting Happy supervisor for directory: %s\n' "$ARG_WORKDIR"

  export ARG_WORKDIR ARG_OPENCODE_PORT ARG_HAPPY_SERVER_URL ARG_HAPPY_WEBAPP_URL ARG_HAPPY_HOME_DIR ARG_HAPPY_DISABLE_CAFFEINATE ARG_HAPPY_EXPERIMENTAL

  local supervisor_cmd
  supervisor_cmd="$(declare -f command_exists decode_b64 expand_home is_true set_happy_env happy_credentials_file happy_configured opencode_url opencode_healthcheck acquire_supervisor_lock ensure_happy_daemon run_supervisor); run_supervisor"

  : > /tmp/happy-coder-supervisor.log
  : > /tmp/happy-coder-daemon.log
  : > /tmp/happy-coder-session.log
  nohup bash -lc "$supervisor_cmd" > /tmp/happy-coder-supervisor.log 2>&1 &
  local supervisor_pid=$!
  sleep 1

  if ! kill -0 "$supervisor_pid" 2> /dev/null; then
    printf 'ERROR: Happy supervisor failed to start\n'
    return 1
  fi

  printf 'Happy supervisor started for OpenCode port %s\n' "$ARG_OPENCODE_PORT"
  printf 'Supervisor logs available at /tmp/happy-coder-supervisor.log\n'
  printf 'Daemon logs available at /tmp/happy-coder-daemon.log\n'
  printf 'Session logs available at /tmp/happy-coder-session.log\n'
}

if ! command_exists happy; then
  echo 'ERROR: Happy is not installed'
  exit 1
fi

start_happy_supervisor
