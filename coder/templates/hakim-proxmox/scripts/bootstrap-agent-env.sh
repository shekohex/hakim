#!/usr/bin/env bash
set -euo pipefail

for required in curl sed; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

PVE_ENDPOINT="${PVE_ENDPOINT%/}"
PVE_NODE_NAME="${PVE_NODE_NAME}"
PVE_VM_ID="${PVE_VM_ID}"
PVE_API_TOKEN="${PVE_API_TOKEN}"
PVE_INSECURE="${PVE_INSECURE:-true}"
CT_AGENT_BOOTSTRAP="${CT_AGENT_BOOTSTRAP}"
PVE_HOME_SOURCE="${PVE_HOME_SOURCE:-}"

AUTH_HEADER="Authorization: PVEAPIToken=${PVE_API_TOKEN}"

curl_flags=(--silent --show-error)
if [[ "${PVE_INSECURE,,}" == "true" || "${PVE_INSECURE}" == "1" ]]; then
  curl_flags+=(--insecure)
fi

api_call() {
  local method="$1"
  local path="$2"
  shift 2

  local response_file
  response_file="$(mktemp)"

  local status
  status="$(curl "${curl_flags[@]}" --output "${response_file}" --write-out '%{http_code}' --request "${method}" "${PVE_ENDPOINT}${path}" -H "${AUTH_HEADER}" "$@")"
  local body
  body="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ "${status}" -ge 400 ]]; then
    printf 'HTTP %s %s failed: %s\n' "${method}" "${path}" "${body}" >&2
    return 1
  fi

  printf '%s' "${body}"
}

api_call_with_status() {
  local method="$1"
  local path="$2"
  shift 2

  local response_file
  response_file="$(mktemp)"

  local status
  status="$(curl "${curl_flags[@]}" --output "${response_file}" --write-out '%{http_code}' --request "${method}" "${PVE_ENDPOINT}${path}" -H "${AUTH_HEADER}" "$@")"
  local body
  body="$(<"${response_file}")"
  rm -f "${response_file}"

  printf '%s\n%s' "${status}" "${body}"
}

json_data_value() {
  sed -n 's/.*"data":"\([^"]*\)".*/\1/p'
}

json_status_value() {
  sed -n 's/.*"status":"\([^"]*\)".*/\1/p'
}

json_exitstatus_value() {
  sed -n 's/.*"exitstatus":"\([^"]*\)".*/\1/p'
}

wait_task() {
  local upid="$1"
  local deadline=$(( $(date +%s) + 300 ))

  while [[ "$(date +%s)" -lt "${deadline}" ]]; do
    local payload status exitstatus
    payload="$(api_call GET "/api2/json/nodes/${PVE_NODE_NAME}/tasks/${upid}/status")"
    status="$(printf '%s' "${payload}" | json_status_value)"

    if [[ "${status}" == "stopped" ]]; then
      exitstatus="$(printf '%s' "${payload}" | json_exitstatus_value)"
      if [[ -z "${exitstatus}" || "${exitstatus}" == "OK" ]]; then
        return 0
      fi
      printf 'task %s failed: %s\n' "${upid}" "${exitstatus}" >&2
      return 1
    fi

    sleep 1
  done

  printf 'task %s timeout\n' "${upid}" >&2
  return 1
}

api_call PUT "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" \
  --data-urlencode "env=CODER_AGENT_BOOTSTRAP=${CT_AGENT_BOOTSTRAP}" >/dev/null

stop_result="$(api_call_with_status POST "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/stop")"
stop_status="$(printf '%s' "${stop_result}" | sed -n '1p')"
stop_body="$(printf '%s' "${stop_result}" | sed -n '2,$p')"

if [[ "${stop_status}" -ge 400 ]]; then
  if [[ "${stop_body}" != *"not running"* ]]; then
    printf 'HTTP POST %s failed: %s\n' "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/stop" "${stop_body}" >&2
    exit 1
  fi
else
  stop_upid="$(printf '%s' "${stop_body}" | json_data_value)"
  if [[ -n "${stop_upid}" ]]; then
    wait_task "${stop_upid}"
  fi
fi

if [[ -n "${PVE_HOME_SOURCE}" ]]; then
  api_call PUT "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" \
    --data-urlencode "mp0=${PVE_HOME_SOURCE},mp=/home/coder,backup=0" >/dev/null
fi

start_result="$(api_call_with_status POST "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/start")"
start_status="$(printf '%s' "${start_result}" | sed -n '1p')"
start_body="$(printf '%s' "${start_result}" | sed -n '2,$p')"

if [[ "${start_status}" -ge 400 ]]; then
  if [[ "${start_body}" != *"already running"* ]]; then
    printf 'HTTP POST %s failed: %s\n' "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/start" "${start_body}" >&2
    exit 1
  fi
else
  start_upid="$(printf '%s' "${start_body}" | json_data_value)"
  if [[ -n "${start_upid}" ]]; then
    wait_task "${start_upid}"
  fi
fi
