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

config_result="$(api_call_with_status GET "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config")"
config_status="$(printf '%s' "${config_result}" | sed -n '1p')"
config_body="$(printf '%s' "${config_result}" | sed -n '2,$p')"

if [[ "${config_status}" -ge 400 ]]; then
  if [[ "${config_body}" == *"does not exist"* || "${config_body}" == *"no such VM"* || "${config_body}" == *"no such CT"* ]]; then
    exit 0
  fi
  printf 'HTTP GET %s failed: %s\n' "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" "${config_body}" >&2
  exit 1
fi

home_mp_key="$(printf '%s' "${config_body}" | sed -n 's/.*"\(mp[0-9]\+\)":"[^"]*mp=\/home\/coder[^"]*".*/\1/p' | sed -n '1p')"
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
  printf 'HTTP PUT %s failed: %s\n' "/api2/json/nodes/${PVE_NODE_NAME}/lxc/${PVE_VM_ID}/config" "${update_body}" >&2
  exit 1
fi
