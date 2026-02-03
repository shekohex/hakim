#!/bin/bash
set -euo pipefail

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
ARG_PORT=${ARG_PORT:-6904}
ARG_UI_PASSWORD=$(echo -n "${ARG_UI_PASSWORD:-}" | base64 -d 2> /dev/null || echo "")

if ! command_exists openchamber; then
  echo "ERROR: OpenChamber is not installed"
  exit 1
fi

cd "$ARG_WORKDIR"

serve_args=(--port "$ARG_PORT")

if [ -n "$ARG_UI_PASSWORD" ]; then
  serve_args+=(--ui-password "$ARG_UI_PASSWORD")
fi

nohup openchamber "${serve_args[@]}" > /tmp/openchamber-serve.log 2>&1 &

echo "OpenChamber server started on port $ARG_PORT"
