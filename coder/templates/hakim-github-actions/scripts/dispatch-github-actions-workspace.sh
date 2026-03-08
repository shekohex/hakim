#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf '%s is required\n' "$name" >&2
    exit 1
  fi
}

for name in GITHUB_API_TOKEN ACTIONS_REPOSITORY ACTIONS_WORKFLOW_FILE ACTIONS_WORKFLOW_REF WORKSPACE_ID WORKSPACE_NAME WORKSPACE_IMAGE CODER_AGENT_URL CODER_AGENT_TOKEN ACTIONS_AGE_PUBLIC_KEY WORKSPACE_TOKEN_SECRET_NAME STOP_SIGNAL_NAME RUN_SIGNAL_NAME; do
  require_env "$name"
done

for tool in curl jq tar uname mktemp sed; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$tool" >&2
    exit 1
  }
done

api_url() {
  local path="$1"
  printf 'https://api.github.com%s' "$path"
}

repo_owner="${ACTIONS_REPOSITORY%%/*}"
repo_name="${ACTIONS_REPOSITORY#*/}"
if [[ -z "${repo_owner}" || -z "${repo_name}" || "${repo_owner}" == "${repo_name}" ]]; then
  printf 'ACTIONS_REPOSITORY must be in owner/repo format\n' >&2
  exit 1
fi

urlencode() {
  jq -rn --arg value "$1" '$value|@uri'
}

curl_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local output_file
  output_file="$(mktemp)"
  local status
  if [[ -n "$data" ]]; then
    status="$(curl -fsS -o "$output_file" -w '%{http_code}' -X "$method" -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer ${GITHUB_API_TOKEN}" -H 'X-GitHub-Api-Version: 2022-11-28' -d "$data" "$(api_url "$path")")"
  else
    status="$(curl -fsS -o "$output_file" -w '%{http_code}' -X "$method" -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer ${GITHUB_API_TOKEN}" -H 'X-GitHub-Api-Version: 2022-11-28' "$(api_url "$path")")"
  fi
  cat "$output_file"
  rm -f "$output_file"
  [[ "$status" =~ ^2 ]]
}

curl_api_maybe() {
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
  printf '%s' "$status"
}

ensure_age() {
  if command -v age >/dev/null 2>&1; then
    AGE_BIN="$(command -v age)"
    return
  fi

  local install_dir archive platform url version
  install_dir="${TMPDIR:-/tmp}/hakim-age"
  AGE_BIN="$install_dir/age/age"
  if [[ -x "$AGE_BIN" ]]; then
    return
  fi

  case "$(uname -m)" in
    x86_64|amd64) platform='linux-amd64' ;;
    aarch64|arm64) platform='linux-arm64' ;;
    *) printf 'unsupported architecture for age download\n' >&2; exit 1 ;;
  esac

  archive="${TMPDIR:-/tmp}/age-${platform}.tar.gz"
  version="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/FiloSottile/age/releases/latest | sed -E 's#.*/tag/v##')"
  url="https://github.com/FiloSottile/age/releases/download/v${version}/age-v${version}-${platform}.tar.gz"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$install_dir"
  rm -f "$archive"
}

ensure_age

curl_api_maybe DELETE "/repos/${repo_owner}/${repo_name}/actions/variables/${STOP_SIGNAL_NAME}" >/dev/null || true
curl_api_maybe DELETE "/repos/${repo_owner}/${repo_name}/actions/variables/${RUN_SIGNAL_NAME}" >/dev/null || true

manifest_json="$(jq -nc \
  --arg workspace_id "$WORKSPACE_ID" \
  --arg workspace_name "$WORKSPACE_NAME" \
  --arg workspace_owner "${WORKSPACE_OWNER:-}" \
  --arg workspace_image "$WORKSPACE_IMAGE" \
  --arg container_memory_mb "${CONTAINER_MEMORY_MB:-}" \
  --arg container_memory_swap_mb "${CONTAINER_MEMORY_SWAP_MB:-}" \
  --arg container_cpus "${CONTAINER_CPUS:-}" \
  --arg coder_agent_url "$CODER_AGENT_URL" \
  --arg coder_agent_token "$CODER_AGENT_TOKEN" \
  '{workspace_id:$workspace_id,workspace_name:$workspace_name,workspace_owner:$workspace_owner,workspace_image:$workspace_image,container_memory_mb:$container_memory_mb,container_memory_swap_mb:$container_memory_swap_mb,container_cpus:$container_cpus,coder_agent_url:$coder_agent_url,coder_agent_token:$coder_agent_token}')"

manifest_file="$(mktemp)"
cipher_file="$(mktemp)"
printf '%s' "$manifest_json" > "$manifest_file"
"$AGE_BIN" --encrypt --armor --recipient "$ACTIONS_AGE_PUBLIC_KEY" --output "$cipher_file" "$manifest_file"
manifest_cipher="$(cat "$cipher_file")"
rm -f "$manifest_file" "$cipher_file"

payload="$(jq -nc \
  --arg ref "$ACTIONS_WORKFLOW_REF" \
  --arg workspace_id "$WORKSPACE_ID" \
  --arg workspace_name "$WORKSPACE_NAME" \
  --arg manifest "$manifest_cipher" \
  --arg workspace_token_secret_name "$WORKSPACE_TOKEN_SECRET_NAME" \
  '{ref:$ref,inputs:{workspace_id:$workspace_id,workspace_name:$workspace_name,manifest:$manifest,workspace_token_secret_name:$workspace_token_secret_name}}')"

curl_api POST "/repos/${repo_owner}/${repo_name}/actions/workflows/$(urlencode "$ACTIONS_WORKFLOW_FILE")/dispatches" "$payload" >/dev/null
