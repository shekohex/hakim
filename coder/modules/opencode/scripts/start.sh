#!/bin/bash
set -euo pipefail

export PATH=/home/coder/.opencode/bin:$PATH
export PATH="$HOME/.bun/bin:$PATH"
if command -v bun > /dev/null 2>&1; then
  GLOBAL_BIN_DIR=$(bun pm bin -g 2> /dev/null || true)
  if [ -n "$GLOBAL_BIN_DIR" ]; then
    export PATH="$GLOBAL_BIN_DIR:$PATH"
  fi
fi

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
  local url="http://localhost:${ARG_PORT}/project/current"
  local max_attempts=30
  local attempt=0

  printf "Waiting for OpenCode server to be ready...\n"
  while [ $attempt -lt $max_attempts ]; do
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
      printf "OpenCode server is ready\n"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  printf "WARNING: OpenCode server may not be ready after %d seconds\n" "$max_attempts"
  return 1
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

start_opencode_server() {
  printf "Starting OpenCode server in directory: %s\n" "$ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  local serve_args=(serve --port "$ARG_PORT" --hostname "$ARG_HOSTNAME" --print-logs)

  if [ -n "$ARG_SESSION_ID" ]; then
    serve_args+=(--session "$ARG_SESSION_ID")
  fi

  if [ "$ARG_CONTINUE" = "true" ]; then
    serve_args+=(--continue)
  fi

  printf "Running: opencode %s\n" "${serve_args[*]}"
  nohup opencode "${serve_args[@]}" > /tmp/opencode-serve.log 2>&1 &

  printf "OpenCode server started on port %s\n" "$ARG_PORT"
  printf "Logs available at /tmp/opencode-serve.log\n"

  wait_for_server
  send_initial_prompt
}

validate_opencode_installation
start_opencode_server
