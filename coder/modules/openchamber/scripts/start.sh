#!/bin/bash
set -euo pipefail

export MIX_HOME=/home/coder/.mix
export HEX_HOME=/home/coder/.hex
export MIX_ARCHIVES=/home/coder/.mix/archives

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_PORT=${ARG_PORT:-6904}
ARG_UI_PASSWORD=$(echo -n "${ARG_UI_PASSWORD:-}" | base64 -d 2> /dev/null || echo "")
ARG_STARTUP_TIMEOUT=${ARG_STARTUP_TIMEOUT:-180}

wait_for_command() {
  local cmd="$1"
  local timeout="$2"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if command_exists "$cmd"; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

wait_for_openchamber() {
  local pid="$1"
  local elapsed=0

  while [ "$elapsed" -lt "$ARG_STARTUP_TIMEOUT" ]; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${ARG_PORT}/health" | grep -q "200"; then
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

if ! command_exists openchamber; then
  echo "ERROR: OpenChamber is not installed"
  exit 1
fi

if ! wait_for_command opencode "$ARG_STARTUP_TIMEOUT"; then
  echo "ERROR: OpenCode command did not become available in time"
  exit 1
fi

cd "$ARG_WORKDIR"

if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${ARG_PORT}/health" | grep -q "200"; then
  echo "OpenChamber is already running on port $ARG_PORT"
  exit 0
fi

serve_args=(--port "$ARG_PORT")

if [ -n "$ARG_UI_PASSWORD" ]; then
  serve_args+=(--ui-password "$ARG_UI_PASSWORD")
fi

if command_exists pkill; then
  pkill -f "openchamber --port ${ARG_PORT}" > /dev/null 2>&1 || true
fi

rm -f "/tmp/openchamber-${ARG_PORT}.json"

nohup openchamber "${serve_args[@]}" > /tmp/openchamber-serve.log 2>&1 &
openchamber_pid=$!

if ! wait_for_openchamber "$openchamber_pid"; then
  echo "ERROR: OpenChamber failed to become healthy on port $ARG_PORT"
  sed -n '1,200p' /tmp/openchamber-serve.log || true
  exit 1
fi

echo "OpenChamber server started on port $ARG_PORT"
