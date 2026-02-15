#!/usr/bin/env bash
set -euo pipefail

for required in curl sed; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

ACTION="${1:-}"
if [[ "${ACTION}" != "ensure" && "${ACTION}" != "delete" ]]; then
  printf 'usage: %s <ensure|delete>\n' "${0}" >&2
  exit 1
fi

PVE_ENDPOINT="${PVE_ENDPOINT%/}"
PVE_NODE_NAME="${PVE_NODE_NAME}"
PVE_API_TOKEN="${PVE_API_TOKEN}"
PVE_INSECURE="${PVE_INSECURE:-true}"
HOME_BIND_PATH="${HOME_BIND_PATH}"

if [[ -z "${PVE_ENDPOINT}" || -z "${PVE_NODE_NAME}" || -z "${PVE_API_TOKEN}" || -z "${HOME_BIND_PATH}" ]]; then
  printf 'PVE_ENDPOINT, PVE_NODE_NAME, PVE_API_TOKEN and HOME_BIND_PATH are required\n' >&2
  exit 1
fi

if [[ ! "${HOME_BIND_PATH}" =~ ^/[a-zA-Z0-9._/-]+$ ]]; then
  printf 'HOME_BIND_PATH must match ^/[a-zA-Z0-9._/-]+$\n' >&2
  exit 1
fi

HOME_BIND_OWNER_UID="${HOME_BIND_OWNER_UID:-101000}"
HOME_BIND_OWNER_GID="${HOME_BIND_OWNER_GID:-101000}"
HOME_BIND_MODE="${HOME_BIND_MODE:-0750}"

if [[ ! "${HOME_BIND_OWNER_UID}" =~ ^[0-9]+$ || ! "${HOME_BIND_OWNER_GID}" =~ ^[0-9]+$ ]]; then
  printf 'HOME_BIND_OWNER_UID and HOME_BIND_OWNER_GID must be numeric\n' >&2
  exit 1
fi

if [[ ! "${HOME_BIND_MODE}" =~ ^[0-7]{4}$ ]]; then
  printf 'HOME_BIND_MODE must be 4-digit octal\n' >&2
  exit 1
fi

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

run_commands() {
  local commands_json="$1"
  local payload upid

  payload="$(api_call POST "/api2/json/nodes/${PVE_NODE_NAME}/execute" --data-urlencode "commands=${commands_json}")"
  upid="$(printf '%s' "${payload}" | json_data_value)"

  if [[ -n "${upid}" ]]; then
    wait_task "${upid}"
  fi
}

if [[ "${ACTION}" == "ensure" ]]; then
  run_commands "[\"mkdir -p -- ${HOME_BIND_PATH}\",\"chown ${HOME_BIND_OWNER_UID}:${HOME_BIND_OWNER_GID} -- ${HOME_BIND_PATH}\",\"chmod ${HOME_BIND_MODE} -- ${HOME_BIND_PATH}\"]"
  exit 0
fi

run_commands "[\"if [ -d ${HOME_BIND_PATH} ]; then rm -rf -- ${HOME_BIND_PATH}; fi\"]"
