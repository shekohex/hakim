#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf '%s is required\n' "$name" >&2
    exit 1
  fi
}

for name in GITHUB_API_TOKEN ACTIONS_REPOSITORY STOP_SIGNAL_NAME RUN_SIGNAL_NAME; do
  require_env "$name"
done

for tool in curl jq mktemp; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$tool" >&2
    exit 1
  }
done

repo_owner="${ACTIONS_REPOSITORY%%/*}"
repo_name="${ACTIONS_REPOSITORY#*/}"

api_url() {
  local path="$1"
  printf 'https://api.github.com%s' "$path"
}

request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local output_file
  output_file="$(mktemp)"
  local status
  if [[ -n "$data" ]]; then
    status="$(curl -sS -o "$output_file" -w '%{http_code}' -X "$method" -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer ${GITHUB_API_TOKEN}" -H 'X-GitHub-Api-Version: 2022-11-28' -d "$data" "$(api_url "$path")")"
  else
    status="$(curl -sS -o "$output_file" -w '%{http_code}' -X "$method" -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer ${GITHUB_API_TOKEN}" -H 'X-GitHub-Api-Version: 2022-11-28' "$(api_url "$path")")"
  fi
  cat "$output_file"
  rm -f "$output_file"
  printf '\n%s' "$status"
}

set_variable() {
  local value="$1"
  local payload
  payload="$(jq -nc --arg name "$STOP_SIGNAL_NAME" --arg value "$value" '{name:$name,value:$value}')"
  local response body status
  response="$(request PATCH "/repos/${repo_owner}/${repo_name}/actions/variables/${STOP_SIGNAL_NAME}" "$payload")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "$status" == "404" ]]; then
    request POST "/repos/${repo_owner}/${repo_name}/actions/variables" "$payload" >/dev/null
    return
  fi
  if [[ ! "$status" =~ ^2 ]]; then
    printf '%s\n' "$body" >&2
    exit 1
  fi
}

get_run_id() {
  local response body status
  response="$(request GET "/repos/${repo_owner}/${repo_name}/actions/variables/${RUN_SIGNAL_NAME}")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "$status" == "404" ]]; then
    return 1
  fi
  if [[ ! "$status" =~ ^2 ]]; then
    printf '%s\n' "$body" >&2
    exit 1
  fi
  printf '%s' "$body" | jq -r '.value'
}

get_run_status() {
  local run_id="$1"
  local response body status
  response="$(request GET "/repos/${repo_owner}/${repo_name}/actions/runs/${run_id}")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ ! "$status" =~ ^2 ]]; then
    printf '%s\n' "$body" >&2
    exit 1
  fi
  printf '%s' "$body" | jq -r '.status'
}

set_variable "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

wait_seconds="${STOP_WAIT_SECONDS:-900}"
interval_seconds="${STOP_POLL_INTERVAL_SECONDS:-5}"
elapsed=0
while (( elapsed < wait_seconds )); do
  if ! run_id="$(get_run_id)"; then
    exit 0
  fi
  status="$(get_run_status "$run_id")"
  if [[ "$status" == "completed" ]]; then
    exit 0
  fi
  sleep "$interval_seconds"
  elapsed=$((elapsed + interval_seconds))
done
