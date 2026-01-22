#!/bin/bash
set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ARG_BRIDGE_HOST=${ARG_BRIDGE_HOST:-""}
ARG_BRIDGE_PORT=${ARG_BRIDGE_PORT:-18790}
ARG_BRIDGE_TLS=${ARG_BRIDGE_TLS:-false}
ARG_BRIDGE_TLS_FINGERPRINT=$(echo -n "${ARG_BRIDGE_TLS_FINGERPRINT:-}" | base64 -d 2>/dev/null || echo "")
ARG_DISPLAY_NAME=$(echo -n "${ARG_DISPLAY_NAME:-}" | base64 -d 2>/dev/null || echo "")
ARG_GATEWAY_WS_URL=${ARG_GATEWAY_WS_URL:-""}
ARG_GATEWAY_TOKEN=$(echo -n "${ARG_GATEWAY_TOKEN:-}" | base64 -d 2>/dev/null || echo "")
ARG_AUTO_APPROVE_PAIRING=${ARG_AUTO_APPROVE_PAIRING:-false}

if [ -z "${ARG_BRIDGE_HOST}" ]; then
  exit 0
fi

if ! command_exists clawdbot; then
  printf "ERROR: clawdbot not installed\n" >&2
  exit 1
fi

node_args=(node run --host "${ARG_BRIDGE_HOST}" --port "${ARG_BRIDGE_PORT}")

if [ "${ARG_BRIDGE_TLS}" = "true" ]; then
  node_args+=(--tls)
  if [ -n "${ARG_BRIDGE_TLS_FINGERPRINT}" ]; then
    node_args+=(--tls-fingerprint "${ARG_BRIDGE_TLS_FINGERPRINT}")
  fi
fi

if [ -n "${ARG_DISPLAY_NAME}" ]; then
  node_args+=(--display-name "${ARG_DISPLAY_NAME}")
fi

nohup clawdbot "${node_args[@]}" >/tmp/clawdbot-node.log 2>&1 &

if [ "${ARG_AUTO_APPROVE_PAIRING}" != "true" ]; then
  exit 0
fi

if [ -z "${ARG_GATEWAY_WS_URL}" ] || [ -z "${ARG_GATEWAY_TOKEN}" ]; then
  exit 0
fi

if ! command_exists jq; then
  exit 0
fi

attempt=0
max_attempts=30
sleep 1

while [ "$attempt" -lt "$max_attempts" ]; do
  pending_json=$(clawdbot gateway call node.pair.list --url "${ARG_GATEWAY_WS_URL}" --token "${ARG_GATEWAY_TOKEN}" --json 2>/dev/null || true)

  if [ -n "${pending_json}" ]; then
    request_id=$(echo "${pending_json}" | jq -r --arg name "${ARG_DISPLAY_NAME}" '((.payload.pending // .pending // [])[]? | select(.displayName == $name) | .requestId) // empty' 2>/dev/null | head -n1 || true)

    if [ -n "${request_id}" ] && [ "${request_id}" != "null" ]; then
      clawdbot gateway call node.pair.approve --url "${ARG_GATEWAY_WS_URL}" --token "${ARG_GATEWAY_TOKEN}" --params "{\"requestId\":\"${request_id}\"}" --json >/dev/null 2>&1 || true
      exit 0
    fi
  fi

  attempt=$((attempt + 1))
  sleep 2
done
