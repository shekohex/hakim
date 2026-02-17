#!/usr/bin/env bash
set -euo pipefail

for required in curl sed base64; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

PVE_ENDPOINT="${PVE_ENDPOINT%/}"
PVE_NODE_NAME="${PVE_NODE_NAME}"
PVE_VM_ID="${PVE_VM_ID}"
PVE_API_TOKEN="${PVE_API_TOKEN}"
PVE_USERNAME="${PVE_USERNAME:-}"
PVE_PASSWORD="${PVE_PASSWORD:-}"
PVE_INSECURE="${PVE_INSECURE:-true}"
CT_AGENT_BOOTSTRAP="${CT_AGENT_BOOTSTRAP}"
CT_RUNTIME_ENV_B64="${CT_RUNTIME_ENV_B64:-}"
PVE_HOME_SOURCE="${PVE_HOME_SOURCE:-}"

AUTH_HEADER="Authorization: PVEAPIToken=${PVE_API_TOKEN}"
PVE_AUTH_COOKIE=""
PVE_CSRF_TOKEN=""

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

json_field_value() {
  local key="$1"
  sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p"
}

session_auth() {
  if [[ -n "${PVE_AUTH_COOKIE}" && -n "${PVE_CSRF_TOKEN}" ]]; then
    return 0
  fi

  if [[ -z "${PVE_USERNAME}" || -z "${PVE_PASSWORD}" ]]; then
    printf 'bind mount requires PVE_USERNAME and PVE_PASSWORD\n' >&2
    return 1
  fi

  local response_file
  response_file="$(mktemp)"

  local status
  status="$(curl "${curl_flags[@]}" --output "${response_file}" --write-out '%{http_code}' --request POST "${PVE_ENDPOINT}/api2/json/access/ticket" --data-urlencode "username=${PVE_USERNAME}" --data-urlencode "password=${PVE_PASSWORD}")"
  local body
  body="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ "${status}" -ge 400 ]]; then
    printf 'HTTP POST /api2/json/access/ticket failed: %s\n' "${body}" >&2
    return 1
  fi

  PVE_AUTH_COOKIE="$(printf '%s' "${body}" | json_field_value ticket)"
  PVE_CSRF_TOKEN="$(printf '%s' "${body}" | json_field_value CSRFPreventionToken)"

  if [[ -z "${PVE_AUTH_COOKIE}" || -z "${PVE_CSRF_TOKEN}" ]]; then
    printf 'failed to parse Proxmox session auth response\n' >&2
    return 1
  fi
}

session_api_call() {
  local method="$1"
  local path="$2"
  shift 2

  session_auth

  local response_file
  response_file="$(mktemp)"

  local status
  status="$(curl "${curl_flags[@]}" --output "${response_file}" --write-out '%{http_code}' --request "${method}" "${PVE_ENDPOINT}${path}" -H "Cookie: PVEAuthCookie=${PVE_AUTH_COOKIE}" -H "CSRFPreventionToken: ${PVE_CSRF_TOKEN}" "$@")"
  local body
  body="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ "${status}" -ge 400 ]]; then
    printf 'HTTP %s %s failed: %s\n' "${method}" "${path}" "${body}" >&2
    return 1
  fi

  printf '%s' "${body}"
}

decode_base64() {
  if printf '%s' "$1" | base64 --decode >/dev/null 2>&1; then
    printf '%s' "$1" | base64 --decode
    return 0
  fi

  if printf '%s' "$1" | base64 -d >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d
    return 0
  fi

  if printf '%s' "$1" | base64 -D >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -D
    return 0
  fi

  return 1
}

RUNTIME_ENV_FILE="$(mktemp)"

cleanup() {
  rm -f "${RUNTIME_ENV_FILE}"
}

trap cleanup EXIT

append_runtime_env_pair() {
  local key="$1"
  local value="$2"

  if [[ -s "${RUNTIME_ENV_FILE}" ]]; then
    printf '\0' >>"${RUNTIME_ENV_FILE}"
  fi

  printf '%s=%s' "${key}" "${value}" >>"${RUNTIME_ENV_FILE}"
}

build_runtime_env_file() {
  local pairs_raw="$1"
  local -a pairs=()
  local pair key encoded value

  : >"${RUNTIME_ENV_FILE}"

  if [[ -n "${pairs_raw}" ]]; then
    IFS=',' read -r -a pairs <<< "${pairs_raw}"

    for pair in "${pairs[@]}"; do
      [[ -n "${pair}" ]] || continue

      key="${pair%%=*}"
      encoded="${pair#*=}"

      if [[ -z "${key}" ]]; then
        continue
      fi

      value="$(decode_base64 "${encoded}")" || {
        printf 'failed to decode env value for key: %s\n' "${key}" >&2
        return 1
      }

      append_runtime_env_pair "${key}" "${value}"
    done
  fi

  append_runtime_env_pair "CODER_AGENT_BOOTSTRAP" "${CT_AGENT_BOOTSTRAP}"
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

build_runtime_env_file "${CT_RUNTIME_ENV_B64}"

api_call PUT "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" \
  --data-urlencode "env@${RUNTIME_ENV_FILE}" >/dev/null

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
  session_api_call PUT "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" \
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
