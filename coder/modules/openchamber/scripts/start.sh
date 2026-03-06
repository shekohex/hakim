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

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_PORT=${ARG_PORT:-6904}
ARG_UI_PASSWORD=$(echo -n "${ARG_UI_PASSWORD:-}" | base64 -d 2> /dev/null || echo "")
ARG_STARTUP_TIMEOUT=${ARG_STARTUP_TIMEOUT:-180}
ARG_REUSE_OPENCODE=${ARG_REUSE_OPENCODE:-false}
ARG_OPENCODE_PORT=${ARG_OPENCODE_PORT:-4096}

resolve_opencode_binary() {
  local candidate
  for candidate in \
    "$HOME/.bun/bin/opencode" \
    "/usr/local/bin/opencode" \
    "/usr/bin/opencode"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command_exists opencode; then
    command -v opencode
    return 0
  fi

  return 1
}

wait_for_opencode_binary() {
  local timeout="$1"
  local elapsed=0
  local opencode_bin

  while [ "$elapsed" -lt "$timeout" ]; do
    opencode_bin="$(resolve_opencode_binary 2> /dev/null || true)"
    if [ -n "$opencode_bin" ] && [ -x "$opencode_bin" ]; then
      printf '%s\n' "$opencode_bin"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

openchamber_healthcheck() {
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:${ARG_PORT}/health" | grep -q "200"
}

supervisor_lock_file() {
  printf '/tmp/openchamber-supervisor-%s.lock\n' "$ARG_PORT"
}

supervisor_launch_state_file() {
  printf '/tmp/openchamber-supervisor-started-%s\n' "$ARG_PORT"
}

wait_for_openchamber() {
  local pid="$1"
  local elapsed=0

  while [ "$elapsed" -lt "$ARG_STARTUP_TIMEOUT" ]; do
    if openchamber_healthcheck; then
      return 0
    fi

    if ! kill -0 "$pid" 2> /dev/null; then
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

wait_for_openchamber_ready() {
  local elapsed=0

  while [ "$elapsed" -lt "$ARG_STARTUP_TIMEOUT" ]; do
    if openchamber_healthcheck; then
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

build_serve_args() {
  OPENCHAMBER_SERVE_ARGS=(--port "$ARG_PORT")

  if [ -n "$ARG_UI_PASSWORD" ]; then
    OPENCHAMBER_SERVE_ARGS+=(--ui-password "$ARG_UI_PASSWORD")
  fi
}

acquire_supervisor_lock() {
  local lock_file
  lock_file="$(supervisor_lock_file)"

  if command_exists flock; then
    exec 9>"$lock_file"
    if ! flock -n 9; then
      printf "OpenChamber supervisor is already running for port %s\n" "$ARG_PORT"
      return 1
    fi
    return 0
  fi

  local lock_dir="${lock_file}.d"
  if ! mkdir "$lock_dir" 2> /dev/null; then
    printf "OpenChamber supervisor is already running for port %s\n" "$ARG_PORT"
    return 1
  fi

  trap "rmdir '$lock_dir' 2> /dev/null || true" EXIT
  return 0
}

supervisor_running() {
  local supervisor_pid="$1"

  if [ -n "$supervisor_pid" ] && kill -0 "$supervisor_pid" 2> /dev/null; then
    return 0
  fi

  local lock_file
  lock_file="$(supervisor_lock_file)"

  if command_exists flock; then
    exec 8>"$lock_file"
    if flock -n 8; then
      flock -u 8
      return 1
    fi
    return 0
  fi

  [ -d "${lock_file}.d" ]
}

stop_supervisor() {
  local supervisor_pid="$1"

  if [ -z "$supervisor_pid" ] || ! kill -0 "$supervisor_pid" 2> /dev/null; then
    return 0
  fi

  if command_exists pkill; then
    pkill -TERM -P "$supervisor_pid" > /dev/null 2>&1 || true
  fi
  kill "$supervisor_pid" 2> /dev/null || true
  sleep 1
  if command_exists pkill; then
    pkill -KILL -P "$supervisor_pid" > /dev/null 2>&1 || true
  fi
  kill -9 "$supervisor_pid" 2> /dev/null || true
}

run_supervisor() {
  local backoff=1
  local max_backoff=30
  local health_failures=0
  local max_health_failures=3

  if ! acquire_supervisor_lock; then
    return 0
  fi

  printf "OpenChamber supervisor started for port %s\n" "$ARG_PORT"

  while true; do
    if openchamber_healthcheck; then
      sleep 5
      continue
    fi

    if ! cd "$ARG_WORKDIR"; then
      printf "ERROR: failed to enter workdir %s\n" "$ARG_WORKDIR"
      sleep "$backoff"
      backoff=$((backoff * 2))
      if [ "$backoff" -gt "$max_backoff" ]; then
        backoff=$max_backoff
      fi
      continue
    fi

    build_serve_args
    local launch_state_file
    launch_state_file="$(supervisor_launch_state_file)"
    rm -f "/tmp/openchamber-${ARG_PORT}.json"
    printf "Running: openchamber --port %s\n" "$ARG_PORT"
    : > "$launch_state_file"
    if [ -n "$ARG_UI_PASSWORD" ]; then
      openchamber "${OPENCHAMBER_SERVE_ARGS[@]}" > /dev/null 2>&1 &
    else
      openchamber "${OPENCHAMBER_SERVE_ARGS[@]}" >> /tmp/openchamber-serve.log 2>&1 &
    fi
    local openchamber_pid=$!

    if wait_for_openchamber "$openchamber_pid"; then
      backoff=1
    fi

    health_failures=0
    while kill -0 "$openchamber_pid" 2> /dev/null; do
      if openchamber_healthcheck; then
        health_failures=0
      else
        health_failures=$((health_failures + 1))
        if [ "$health_failures" -ge "$max_health_failures" ]; then
          printf "OpenChamber healthcheck failed %s times, restarting\n" "$health_failures"
          kill "$openchamber_pid" 2> /dev/null || true
          sleep 1
          kill -9 "$openchamber_pid" 2> /dev/null || true
          break
        fi
      fi
      sleep 5
    done

    wait "$openchamber_pid" 2> /dev/null || true

    printf "OpenChamber exited, restarting in %s seconds\n" "$backoff"
    sleep "$backoff"
    backoff=$((backoff * 2))
    if [ "$backoff" -gt "$max_backoff" ]; then
      backoff=$max_backoff
    fi
  done
}

start_openchamber_server() {
  printf "Starting OpenChamber supervisor for directory: %s\n" "$ARG_WORKDIR"

  local service_was_healthy=false
  if openchamber_healthcheck; then
    service_was_healthy=true
  fi

  export ARG_WORKDIR ARG_PORT ARG_UI_PASSWORD ARG_STARTUP_TIMEOUT ARG_REUSE_OPENCODE ARG_OPENCODE_PORT

  local supervisor_cmd
  supervisor_cmd="$(declare -f command_exists openchamber_healthcheck supervisor_lock_file supervisor_launch_state_file wait_for_openchamber build_serve_args acquire_supervisor_lock run_supervisor); run_supervisor"
  local launch_state_file
  launch_state_file="$(supervisor_launch_state_file)"

  rm -f "$launch_state_file"
  : > /tmp/openchamber-supervisor.log
  : > /tmp/openchamber-serve.log
  nohup bash -lc "$supervisor_cmd" > /tmp/openchamber-supervisor.log 2>&1 &
  local supervisor_pid=$!
  printf "OpenChamber supervisor started on port %s\n" "$ARG_PORT"
  printf "Supervisor logs available at /tmp/openchamber-supervisor.log\n"
  printf "OpenChamber logs available at /tmp/openchamber-serve.log\n"

  if ! wait_for_openchamber_ready; then
    printf "ERROR: OpenChamber failed to become healthy on port %s\n" "$ARG_PORT"
    printf "Supervisor logs available at /tmp/openchamber-supervisor.log\n"
    printf "OpenChamber logs available at /tmp/openchamber-serve.log\n"
    stop_supervisor "$supervisor_pid"
    return 1
  fi

  if ! supervisor_running "$supervisor_pid"; then
    printf "ERROR: OpenChamber supervisor is not running for port %s\n" "$ARG_PORT"
    sed -n '1,200p' /tmp/openchamber-supervisor.log || true
    stop_supervisor "$supervisor_pid"
    return 1
  fi

  if [ -f "$launch_state_file" ]; then
    printf "OpenChamber server started on port %s\n" "$ARG_PORT"
  elif [ "$service_was_healthy" = "true" ]; then
    printf "OpenChamber is already running on port %s\n" "$ARG_PORT"
  else
    printf "OpenChamber server started on port %s\n" "$ARG_PORT"
  fi
}

if ! command_exists openchamber; then
  echo "ERROR: OpenChamber is not installed"
  exit 1
fi

if [ "$ARG_REUSE_OPENCODE" = "true" ]; then
  echo "OpenChamber configured to reuse external OpenCode server on port $ARG_OPENCODE_PORT"
  export OPENCODE_SKIP_START=true
  export OPENCODE_PORT=$ARG_OPENCODE_PORT
fi

OPENCODE_BIN="$(wait_for_opencode_binary "$ARG_STARTUP_TIMEOUT" || true)"
if [ -z "$OPENCODE_BIN" ]; then
  echo "ERROR: OpenCode command did not become available in time"
  exit 1
fi
export OPENCODE_BINARY="$OPENCODE_BIN"
export PATH="$(dirname "$OPENCODE_BIN"):$PATH"

start_openchamber_server
