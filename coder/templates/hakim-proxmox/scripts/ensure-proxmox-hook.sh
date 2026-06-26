#!/usr/bin/env bash
set -euo pipefail

for required in curl sed mktemp; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

PVE_ENDPOINT="${PVE_ENDPOINT%/}"
PVE_NODE_NAME="${PVE_NODE_NAME:?PVE_NODE_NAME is required}"
PVE_VM_ID="${PVE_VM_ID:-}"
PVE_USERNAME="${PVE_USERNAME:?PVE_USERNAME is required}"
PVE_PASSWORD="${PVE_PASSWORD:?PVE_PASSWORD is required}"
PVE_INSECURE="${PVE_INSECURE:-true}"
PVE_HOOKSCRIPT_ID="${PVE_HOOKSCRIPT_ID:?PVE_HOOKSCRIPT_ID is required}"
PVE_HOOKSCRIPT_SOURCE="${PVE_HOOKSCRIPT_SOURCE:-}"
PVE_WORKSPACE_TRANSITION="${PVE_WORKSPACE_TRANSITION:-start}"

curl_flags=(--silent --show-error)
if [[ "${PVE_INSECURE,,}" == "true" || "${PVE_INSECURE}" == "1" ]]; then
  curl_flags+=(--insecure)
fi

api_call_with_status() {
  local method="$1"
  local path="$2"
  shift 2
  local response_file status body
  response_file="$(mktemp)"
  status="$(curl "${curl_flags[@]}" --output "${response_file}" --write-out '%{http_code}' --request "${method}" "${PVE_ENDPOINT}${path}" -b "PVEAuthCookie=${PVE_AUTH_COOKIE}" -H "CSRFPreventionToken: ${PVE_CSRF_TOKEN}" "$@")"
  body="$(<"${response_file}")"
  rm -f "${response_file}"
  printf '%s\n%s' "${status}" "${body}"
}

json_data_value() {
  sed -n 's/.*"data":"\([^"]*\)".*/\1/p'
}

json_field_value() {
  local key="$1"
  sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p"
}

wait_task() {
  local upid="$1"
  local escaped_upid task_result task_status task_body task_state task_exitstatus
  if [[ -z "${upid}" ]]; then
    return 0
  fi

  escaped_upid="${upid//:/%3A}"
  for _ in {1..120}; do
    task_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/tasks/${escaped_upid}/status")"
    task_status="$(printf '%s' "${task_result}" | sed -n '1p')"
    task_body="$(printf '%s' "${task_result}" | sed -n '2,$p')"
    if [[ "${task_status}" -ge 400 ]]; then
      printf 'HTTP GET task status failed: %s\n' "${task_body}" >&2
      exit 1
    fi

    task_state="$(printf '%s' "${task_body}" | json_field_value status)"
    if [[ "${task_state}" == "stopped" ]]; then
      task_exitstatus="$(printf '%s' "${task_body}" | json_field_value exitstatus)"
      if [[ -n "${task_exitstatus}" && "${task_exitstatus}" != "OK" ]]; then
        printf 'Proxmox task failed: %s\n' "${task_body}" >&2
        exit 1
      fi
      return 0
    fi
    sleep 1
  done

  printf 'timed out waiting for Proxmox task: %s\n' "${upid}" >&2
  exit 1
}

ticket_file="$(mktemp)"
ticket_status="$(curl "${curl_flags[@]}" --output "${ticket_file}" --write-out '%{http_code}' --request POST "${PVE_ENDPOINT}/api2/json/access/ticket" --data-urlencode "username=${PVE_USERNAME}" --data-urlencode "password=${PVE_PASSWORD}")"
ticket_body="$(<"${ticket_file}")"
rm -f "${ticket_file}"
if [[ "${ticket_status}" -ge 400 ]]; then
  printf 'HTTP POST access/ticket failed: %s\n' "${ticket_body}" >&2
  exit 1
fi

PVE_AUTH_COOKIE="$(printf '%s' "${ticket_body}" | json_field_value ticket)"
PVE_CSRF_TOKEN="$(printf '%s' "${ticket_body}" | json_field_value CSRFPreventionToken)"
if [[ -z "${PVE_AUTH_COOKIE}" || -z "${PVE_CSRF_TOKEN}" ]]; then
  printf 'failed to parse Proxmox session auth response\n' >&2
  exit 1
fi

if [[ -n "${PVE_HOOKSCRIPT_SOURCE}" ]]; then
  hook_storage="${PVE_HOOKSCRIPT_ID%%:*}"
  hook_path="${PVE_HOOKSCRIPT_ID#*:}"
  hook_name="${hook_path##*/}"
  if [[ ! -f "${PVE_HOOKSCRIPT_SOURCE}" ]]; then
    printf 'hookscript source not found: %s\n' "${PVE_HOOKSCRIPT_SOURCE}" >&2
    exit 1
  fi
  upload_file="$(mktemp)"
  upload_status="$(curl "${curl_flags[@]}" --output "${upload_file}" --write-out '%{http_code}' --request POST "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE_NAME}/storage/${hook_storage}/upload" -b "PVEAuthCookie=${PVE_AUTH_COOKIE}" -H "CSRFPreventionToken: ${PVE_CSRF_TOKEN}" -F content=snippets -F "filename=@${PVE_HOOKSCRIPT_SOURCE};filename=${hook_name}")"
  upload_body="$(<"${upload_file}")"
  rm -f "${upload_file}"
  if [[ "${upload_status}" -ge 400 && "${upload_body}" == *"value 'snippets'"* && "${upload_body}" == *"enumeration"* ]]; then
    printf 'hookscript upload skipped: storage upload API does not accept snippets\n' >&2
  elif [[ "${upload_status}" -ge 400 && "${upload_body}" != *"file already exists"* ]]; then
    printf 'HTTP POST hookscript upload failed: %s\n' "${upload_body}" >&2
    exit 1
  fi
fi

if [[ -z "${PVE_VM_ID}" ]]; then
  exit 0
fi

config_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config")"
config_status="$(printf '%s' "${config_result}" | sed -n '1p')"
config_body="$(printf '%s' "${config_result}" | sed -n '2,$p')"
if [[ "${config_status}" -ge 400 ]]; then
  printf 'HTTP GET config failed: %s\n' "${config_body}" >&2
  exit 1
fi

hookscript_present=false
if [[ "${config_body}" == *"\"hookscript\":\"${PVE_HOOKSCRIPT_ID}\""* ]]; then
  hookscript_present=true
fi

status_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/current")"
status_body="$(printf '%s' "${status_result}" | sed -n '2,$p')"
was_running=false
if [[ "${status_body}" == *'"status":"running"'* ]]; then
  was_running=true
fi

if [[ "${hookscript_present}" == "false" && "${was_running}" == "true" ]]; then
  stop_result="$(api_call_with_status POST "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/stop")"
  stop_status="$(printf '%s' "${stop_result}" | sed -n '1p')"
  stop_body="$(printf '%s' "${stop_result}" | sed -n '2,$p')"
  if [[ "${stop_status}" -lt 400 ]]; then
    wait_task "$(printf '%s' "${stop_body}" | json_data_value)"
  elif [[ "${stop_body}" != *"not running"* ]]; then
    printf 'HTTP POST stop failed: %s\n' "${stop_body}" >&2
    exit 1
  fi
fi

if [[ "${hookscript_present}" == "false" ]]; then
  hook_result="$(api_call_with_status PUT "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" --data-urlencode "hookscript=${PVE_HOOKSCRIPT_ID}")"
  hook_status="$(printf '%s' "${hook_result}" | sed -n '1p')"
  hook_body="$(printf '%s' "${hook_result}" | sed -n '2,$p')"
  if [[ "${hook_status}" -ge 400 ]]; then
    printf 'HTTP PUT hookscript failed: %s\n' "${hook_body}" >&2
    exit 1
  fi
fi

if [[ "${hookscript_present}" == "false" && "${was_running}" == "true" ]]; then
  start_result="$(api_call_with_status POST "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/start")"
  start_status="$(printf '%s' "${start_result}" | sed -n '1p')"
  start_body="$(printf '%s' "${start_result}" | sed -n '2,$p')"
  if [[ "${start_status}" -ge 400 && "${start_body}" != *"already running"* ]]; then
    printf 'HTTP POST start failed: %s\n' "${start_body}" >&2
    exit 1
  fi
  if [[ "${start_status}" -lt 400 ]]; then
    wait_task "$(printf '%s' "${start_body}" | json_data_value)"
  fi
fi

config_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config")"
config_status="$(printf '%s' "${config_result}" | sed -n '1p')"
config_body="$(printf '%s' "${config_result}" | sed -n '2,$p')"
if [[ "${config_status}" -ge 400 ]]; then
  printf 'HTTP GET config failed: %s\n' "${config_body}" >&2
  exit 1
fi

if [[ "${PVE_WORKSPACE_TRANSITION}" == "start" && "${config_body}" == *"hakim_home=enabled"* && "${config_body}" != *"mp=/home/coder"* ]]; then
  status_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/current")"
  status_body="$(printf '%s' "${status_result}" | sed -n '2,$p')"
  if [[ "${status_body}" == *'"status":"running"'* ]]; then
    stop_result="$(api_call_with_status POST "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/stop")"
    stop_status="$(printf '%s' "${stop_result}" | sed -n '1p')"
    stop_body="$(printf '%s' "${stop_result}" | sed -n '2,$p')"
    if [[ "${stop_status}" -ge 400 && "${stop_body}" != *"not running"* ]]; then
      printf 'HTTP POST stop failed: %s\n' "${stop_body}" >&2
      exit 1
    fi
    if [[ "${stop_status}" -lt 400 ]]; then
      wait_task "$(printf '%s' "${stop_body}" | json_data_value)"
    fi
  fi

  start_result="$(api_call_with_status POST "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/status/start")"
  start_status="$(printf '%s' "${start_result}" | sed -n '1p')"
  start_body="$(printf '%s' "${start_result}" | sed -n '2,$p')"
  if [[ "${start_status}" -ge 400 && "${start_body}" != *"already running"* ]]; then
    printf 'HTTP POST start failed: %s\n' "${start_body}" >&2
    exit 1
  fi
  if [[ "${start_status}" -lt 400 ]]; then
    wait_task "$(printf '%s' "${start_body}" | json_data_value)"
  fi
fi
