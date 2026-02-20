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
export PATH=/home/coder/.opencode/bin:$PATH
export PATH="$HOME/.bun/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_SESSION_ID=${ARG_SESSION_ID:-}
ARG_CONTINUE=${ARG_CONTINUE:-false}
ARG_PORT=${ARG_PORT:-4096}
ARG_HOSTNAME=${ARG_HOSTNAME:-"0.0.0.0"}

printf "=== START CONFIG ===\n"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_CONTINUE: %s\n" "$ARG_CONTINUE"
printf "ARG_SESSION_ID: %s\n" "$ARG_SESSION_ID"
printf "ARG_PORT: %s\n" "$ARG_PORT"
printf "ARG_HOSTNAME: %s\n" "$ARG_HOSTNAME"
if [ -n "$ARG_AI_PROMPT" ]; then
  printf "ARG_AI_PROMPT: [AI PROMPT RECEIVED]\n"
else
  printf "ARG_AI_PROMPT: [NOT PROVIDED]\n"
fi
printf "==================================\n"

validate_opencode_installation() {
  if ! command_exists opencode; then
    printf "ERROR: OpenCode not installed. Set install_opencode to true\n"
    exit 1
  fi
}

wait_for_server() {
  local max_attempts=60
  local attempt=0

  printf "Waiting for OpenCode server to be ready...\n"
  while [ $attempt -lt $max_attempts ]; do
    if opencode_healthcheck; then
      printf "OpenCode server is ready\n"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  printf "WARNING: OpenCode server may not be ready after %d seconds\n" "$max_attempts"
  return 1
}

opencode_healthcheck() {
  local url="http://localhost:${ARG_PORT}/global/health"
  curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"
}

send_initial_prompt() {
  if [ -n "$ARG_AI_PROMPT" ]; then
    printf "Sending initial prompt to OpenCode...\n"
    
    local prompt="$ARG_AI_PROMPT"
    if [ "$ARG_REPORT_TASKS" = "true" ]; then
      prompt="Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_AI_PROMPT"
    fi

    nohup opencode run --attach "http://localhost:${ARG_PORT}" --format json "$prompt" > /tmp/opencode-prompt.log 2>&1 &
    printf "Initial prompt sent\n"
  fi
}

build_serve_args() {
  OPENCODE_SERVE_ARGS=(serve --port "$ARG_PORT" --hostname "$ARG_HOSTNAME" --print-logs)

  if [ -n "$ARG_SESSION_ID" ]; then
    OPENCODE_SERVE_ARGS+=(--session "$ARG_SESSION_ID")
  fi

  if [ "$ARG_CONTINUE" = "true" ]; then
    OPENCODE_SERVE_ARGS+=(--continue)
  fi
}

acquire_supervisor_lock() {
  local lock_file="/tmp/opencode-supervisor-${ARG_PORT}.lock"

  if command_exists flock; then
    exec 9>"$lock_file"
    if ! flock -n 9; then
      printf "OpenCode supervisor is already running for port %s\n" "$ARG_PORT"
      return 1
    fi
    return 0
  fi

  local lock_dir="${lock_file}.d"
  if ! mkdir "$lock_dir" 2> /dev/null; then
    printf "OpenCode supervisor is already running for port %s\n" "$ARG_PORT"
    return 1
  fi

  trap 'rmdir "$lock_dir" 2> /dev/null || true' EXIT
  return 0
}

run_supervisor() {
  local prompt_state_file="/tmp/opencode-prompt-sent-${ARG_PORT}"
  local backoff=1
  local max_backoff=30
  local health_failures=0
  local max_health_failures=3

  if ! acquire_supervisor_lock; then
    return 0
  fi

  printf "OpenCode supervisor started for port %s\n" "$ARG_PORT"

  while true; do
    if opencode_healthcheck; then
      if [ -n "$ARG_AI_PROMPT" ] && [ ! -f "$prompt_state_file" ]; then
        send_initial_prompt
        : > "$prompt_state_file"
      fi
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
    printf "Running: opencode %s\n" "${OPENCODE_SERVE_ARGS[*]}"
    opencode "${OPENCODE_SERVE_ARGS[@]}" >> /tmp/opencode-serve.log 2>&1 &
    local opencode_pid=$!

    if wait_for_server; then
      backoff=1
      if [ -n "$ARG_AI_PROMPT" ] && [ ! -f "$prompt_state_file" ]; then
        send_initial_prompt
        : > "$prompt_state_file"
      fi
    fi

    health_failures=0
    while kill -0 "$opencode_pid" 2> /dev/null; do
      if opencode_healthcheck; then
        health_failures=0
      else
        health_failures=$((health_failures + 1))
        if [ "$health_failures" -ge "$max_health_failures" ]; then
          printf "OpenCode healthcheck failed %s times, restarting\n" "$health_failures"
          kill "$opencode_pid" 2> /dev/null || true
          sleep 1
          kill -9 "$opencode_pid" 2> /dev/null || true
          break
        fi
      fi
      sleep 5
    done

    wait "$opencode_pid" 2> /dev/null || true

    printf "OpenCode exited, restarting in %s seconds\n" "$backoff"
    sleep "$backoff"
    backoff=$((backoff * 2))
    if [ "$backoff" -gt "$max_backoff" ]; then
      backoff=$max_backoff
    fi
  done
}

start_opencode_server() {
  printf "Starting OpenCode supervisor for directory: %s\n" "$ARG_WORKDIR"

  export ARG_WORKDIR ARG_AI_PROMPT ARG_REPORT_TASKS ARG_SESSION_ID ARG_CONTINUE ARG_PORT ARG_HOSTNAME

  local supervisor_cmd
  supervisor_cmd="$(declare -f command_exists opencode_healthcheck wait_for_server send_initial_prompt build_serve_args acquire_supervisor_lock run_supervisor); run_supervisor"

  nohup bash -lc "$supervisor_cmd" > /tmp/opencode-supervisor.log 2>&1 &
  printf "OpenCode supervisor started on port %s\n" "$ARG_PORT"
  printf "Supervisor logs available at /tmp/opencode-supervisor.log\n"
  printf "OpenCode logs available at /tmp/opencode-serve.log\n"
}

validate_opencode_installation
start_opencode_server
