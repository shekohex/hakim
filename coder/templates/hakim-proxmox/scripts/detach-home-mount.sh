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
HOME_MOUNT_PATH="${HOME_MOUNT_PATH:-/home/coder}"
TASK_WAIT_SEC="${TASK_WAIT_SEC:-60}"
TASK_POLL_SEC="${TASK_POLL_SEC:-1}"

if [[ -z "${PVE_ENDPOINT}" || -z "${PVE_NODE_NAME}" || -z "${PVE_VM_ID}" || -z "${PVE_API_TOKEN}" ]]; then
  printf 'PVE_ENDPOINT, PVE_NODE_NAME, PVE_VM_ID and PVE_API_TOKEN are required\n' >&2
  exit 1
fi

if [[ ! "${PVE_VM_ID}" =~ ^[0-9]+$ ]]; then
  printf 'PVE_VM_ID must be numeric\n' >&2
  exit 1
fi

if [[ ! "${TASK_WAIT_SEC}" =~ ^[0-9]+$ || ! "${TASK_POLL_SEC}" =~ ^[0-9]+$ || "${TASK_POLL_SEC}" -lt 1 ]]; then
  printf 'TASK_WAIT_SEC and TASK_POLL_SEC must be positive integers\n' >&2
  exit 1
fi

AUTH_HEADER="Authorization: PVEAPIToken=${PVE_API_TOKEN}"

curl_flags=(--silent --show-error)
if [[ "${PVE_INSECURE,,}" == "true" || "${PVE_INSECURE}" == "1" ]]; then
  curl_flags+=(--insecure)
fi

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

wait_task() {
  local upid="$1"
  local elapsed=0

  while [[ "${elapsed}" -lt "${TASK_WAIT_SEC}" ]]; do
    local status_result status_code status_body task_status exit_status
    status_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/tasks/${upid}/status")"
    status_code="$(printf '%s' "${status_result}" | sed -n '1p')"
    status_body="$(printf '%s' "${status_result}" | sed -n '2,$p')"

    if [[ "${status_code}" -ge 400 ]]; then
      printf 'HTTP GET task status failed: %s\n' "${status_body}" >&2
      return 1
    fi

    task_status="$(printf '%s' "${status_body}" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
    exit_status="$(printf '%s' "${status_body}" | sed -n 's/.*"exitstatus":"\([^"]*\)".*/\1/p')"

    if [[ "${task_status}" == "stopped" ]]; then
      if [[ "${exit_status}" == "OK" ]]; then
        return 0
      fi
      printf 'detach task failed: %s\n' "${exit_status}" >&2
      return 1
    fi

    sleep "${TASK_POLL_SEC}"
    elapsed=$((elapsed + TASK_POLL_SEC))
  done

  printf 'detach task timeout after %s seconds\n' "${TASK_WAIT_SEC}" >&2
  return 1
}

config_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config")"
config_status="$(printf '%s' "${config_result}" | sed -n '1p')"
config_body="$(printf '%s' "${config_result}" | sed -n '2,$p')"

if [[ "${config_status}" -ge 400 ]]; then
  if [[ "${config_body}" == *"does not exist"* || "${config_body}" == *"no such VM"* || "${config_body}" == *"no such CT"* ]]; then
    exit 0
  fi
  printf 'HTTP GET config failed: %s\n' "${config_body}" >&2
  exit 1
fi

home_mount_path_escaped="$(printf '%s' "${HOME_MOUNT_PATH}" | sed 's/[.[\*^$()+?{}|]/\\&/g; s/\//\\\//g')"
home_mp_key="$(printf '%s' "${config_body}" | sed -n "s/.*\"\(mp[0-9]\\+\)\":\"[^\"]*mp=${home_mount_path_escaped}[^\"]*\".*/\1/p" | sed -n '1p')"

if [[ -z "${home_mp_key}" ]]; then
  exit 0
fi

update_result="$(api_call_with_status PUT "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" --data-urlencode "delete=${home_mp_key}")"
update_status="$(printf '%s' "${update_result}" | sed -n '1p')"
update_body="$(printf '%s' "${update_result}" | sed -n '2,$p')"

if [[ "${update_status}" -ge 400 ]]; then
  if [[ "${update_body}" == *"does not exist"* || "${update_body}" == *"no such VM"* || "${update_body}" == *"no such CT"* || "${update_body}" == *"property is not defined"* ]]; then
    exit 0
  fi
  printf 'HTTP PUT config delete failed: %s\n' "${update_body}" >&2
  exit 1
fi

upid="$(printf '%s' "${update_body}" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')"
if [[ -n "${upid}" ]]; then
  wait_task "${upid}"
fi
