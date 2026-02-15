#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_STATE_FILE="/var/lib/vz/template/cache/.hakim-oci-digests.tsv"
readonly DEFAULT_VARIANTS=(base php dotnet js rust elixir)
readonly DEFAULT_REGISTRY_NAMESPACE="ghcr.io/shekohex"

NODE_NAME="${NODE_NAME:-$(hostname -s)}"
DATASTORE_ID="${DATASTORE_ID:-local}"
TEMPLATE_TAG="${TEMPLATE_TAG:-latest}"
REGISTRY_NAMESPACE="${OCI_REGISTRY_NAMESPACE:-${DEFAULT_REGISTRY_NAMESPACE}}"
STATE_FILE="${DIGEST_STATE_FILE:-${DEFAULT_STATE_FILE}}"
FORCE_REPLACE=false
CHECK_REMOTE_DIGEST=false
USE_GH_AUTH_TOKEN=false
DRY_RUN=false
GH_TOKEN_VALUE="${GH_TOKEN:-}"
GH_USERNAME="${GH_USERNAME:-}"

declare -a REQUESTED_VARIANTS=()
declare -a REQUESTED_IMAGES=()
declare -a TARGET_REFERENCES=()
declare -a TARGET_FILENAMES=()

parse_bool() {
  local value="${1:-}"
  case "${value,,}" in
  1 | true | yes | on)
    printf 'true'
    ;;
  *)
    printf 'false'
    ;;
  esac
}

FORCE_REPLACE="$(parse_bool "${FORCE_REPLACE:-0}")"
CHECK_REMOTE_DIGEST="$(parse_bool "${CHECK_REMOTE_DIGEST:-0}")"
USE_GH_AUTH_TOKEN="$(parse_bool "${USE_GH_AUTH_TOKEN:-0}")"
DRY_RUN="$(parse_bool "${DRY_RUN:-0}")"

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: pull-oci-templates.sh [options]

Pull Hakim OCI images into Proxmox CT template storage.

Options:
  -n, --node <name>              Proxmox node name (default: hostname -s)
  -s, --datastore <id>           Proxmox template datastore (default: local)
  -t, --tag <tag>                Image tag for variants (default: latest)
  -r, --registry <namespace>     Registry namespace (default: ghcr.io/shekohex)
      --local-registry <ns>      Alias for --registry (example: 192.168.1.105:5000/hakim)
  -v, --variant <name>           Pull one variant (repeatable)
      --variants <csv>           Pull comma-separated variants
  -i, --image <reference>        Pull explicit OCI image reference (repeatable)
  -f, --force-replace            Replace existing templates unconditionally
      --check-remote-digest      Compare GHCR digest and replace when changed
      --state-file <path>        Digest state file (default: /var/lib/vz/template/cache/.hakim-oci-digests.tsv)
      --use-gh-auth-token        Resolve token via `gh auth token`
      --gh-token <token>         GH token for digest checks/authfile generation
      --gh-username <name>       GH username for authfile (default from `gh api /user`)
      --dry-run                  Print actions without applying
  -h, --help                     Show this help

Examples:
  pull-oci-templates.sh
  pull-oci-templates.sh --variant js --tag latest
  pull-oci-templates.sh --variants base,elixir --tag v2026.02.14
  pull-oci-templates.sh --image ghcr.io/shekohex/hakim-js:latest
  pull-oci-templates.sh --check-remote-digest --use-gh-auth-token
  pull-oci-templates.sh --registry 192.168.1.105:5000/hakim --variants base,js
EOF
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

has_variant() {
  local requested="$1"
  local variant
  for variant in "${DEFAULT_VARIANTS[@]}"; do
    if [[ "${variant}" == "${requested}" ]]; then
      return 0
    fi
  done
  return 1
}

sanitize_filename_part() {
  local value="$1"
  value="${value//\//-}"
  value="${value//:/-}"
  value="${value//[^a-zA-Z0-9_.-]/-}"
  printf '%s' "${value}"
}

build_variant_reference() {
  local variant="$1"
  case "${variant}" in
  base)
    printf '%s/hakim-base:%s' "${REGISTRY_NAMESPACE}" "${TEMPLATE_TAG}"
    ;;
  php | dotnet | js | rust | elixir)
    printf '%s/hakim-%s:%s' "${REGISTRY_NAMESPACE}" "${variant}" "${TEMPLATE_TAG}"
    ;;
  *)
    die "unsupported variant: ${variant}"
    ;;
  esac
}

build_variant_filename() {
  local variant="$1"
  printf 'hakim-%s_%s.tar' "${variant}" "${TEMPLATE_TAG}"
}

build_pull_filename() {
  local file_name="$1"
  printf '%s' "${file_name%.tar}"
}

build_image_filename() {
  local reference="$1"
  local image_tag="${reference##*/}"
  local image_name="${image_tag%%:*}"
  local image_ref_tag="${image_tag##*:}"

  if [[ "${image_name}" == "${image_ref_tag}" ]]; then
    die "image reference must include tag: ${reference}"
  fi

  image_name="$(sanitize_filename_part "${image_name}")"
  image_ref_tag="$(sanitize_filename_part "${image_ref_tag}")"

  printf '%s_%s.tar' "${image_name}" "${image_ref_tag}"
}

volume_exists() {
  local volume_id="$1"
  pvesm list "${DATASTORE_ID}" --content vztmpl | awk '{print $1}' | grep -Fxq "${volume_id}"
}

legacy_double_tar_volume_id() {
  local volume_id="$1"
  printf '%s.tar' "${volume_id}"
}

resolve_existing_volume_id() {
  local volume_id="$1"
  local legacy_id

  if volume_exists "${volume_id}"; then
    printf '%s' "${volume_id}"
    return 0
  fi

  legacy_id="$(legacy_double_tar_volume_id "${volume_id}")"
  if volume_exists "${legacy_id}"; then
    printf '%s' "${legacy_id}"
    return 0
  fi

  return 1
}

ensure_state_file() {
  local state_dir
  state_dir="$(dirname "${STATE_FILE}")"

  if [[ ! -d "${state_dir}" ]]; then
    if [[ "${DRY_RUN}" == "false" ]]; then
      mkdir -p "${state_dir}"
    fi
  fi

  if [[ "${DRY_RUN}" == "false" ]]; then
    touch "${STATE_FILE}"
  fi
}

read_stored_digest() {
  local volume_id="$1"
  if [[ ! -f "${STATE_FILE}" ]]; then
    return 0
  fi

  awk -v key="${volume_id}" '$1 == key {print $2}' "${STATE_FILE}" | tail -n 1
}

write_stored_digest() {
  local volume_id="$1"
  local digest="$2"
  local temp_file

  temp_file="$(mktemp)"
  if [[ -f "${STATE_FILE}" ]]; then
    awk -v key="${volume_id}" '$1 != key {print $0}' "${STATE_FILE}" >"${temp_file}"
  fi
  printf '%s %s\n' "${volume_id}" "${digest}" >>"${temp_file}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    rm -f "${temp_file}"
    return 0
  fi

  mv "${temp_file}" "${STATE_FILE}"
}

get_ghcr_digest() {
  local reference="$1"
  local image_path tag owner package digest

  [[ "${reference}" == ghcr.io/*:* ]] || return 0

  image_path="${reference#ghcr.io/}"
  tag="${image_path##*:}"
  image_path="${image_path%:*}"
  owner="${image_path%%/*}"
  package="${image_path#*/}"

  if [[ -z "${owner}" || -z "${package}" || "${owner}" == "${package}" ]]; then
    return 0
  fi

  digest="$(gh api "/users/${owner}/packages/container/${package}/versions?per_page=100" --jq ".[] | select((.metadata.container.tags // []) | index(\"${tag}\")) | .name" 2>/dev/null | head -n 1 || true)"
  if [[ -z "${digest}" ]]; then
    digest="$(gh api "/orgs/${owner}/packages/container/${package}/versions?per_page=100" --jq ".[] | select((.metadata.container.tags // []) | index(\"${tag}\")) | .name" 2>/dev/null | head -n 1 || true)"
  fi

  printf '%s' "${digest}"
}

setup_ghcr_auth() {
  local token="$1"
  local username="$2"
  local auth_file auth_b64

  auth_file="$(mktemp)"
  auth_b64="$(printf '%s:%s' "${username}" "${token}" | base64 | tr -d '\n')"

  cat >"${auth_file}" <<EOF
{"auths":{"ghcr.io":{"auth":"${auth_b64}","username":"${username}","password":"${token}"}}}
EOF

  export REGISTRY_AUTH_FILE="${auth_file}"
  trap 'rm -f "${REGISTRY_AUTH_FILE:-}"' EXIT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --node)
    [[ $# -gt 1 ]] || die "missing value for $1"
    NODE_NAME="$2"
    shift 2
    ;;
  -s | --datastore)
    [[ $# -gt 1 ]] || die "missing value for $1"
    DATASTORE_ID="$2"
    shift 2
    ;;
  -t | --tag)
    [[ $# -gt 1 ]] || die "missing value for $1"
    TEMPLATE_TAG="$2"
    shift 2
    ;;
  -r | --registry)
    [[ $# -gt 1 ]] || die "missing value for $1"
    REGISTRY_NAMESPACE="${2%/}"
    shift 2
    ;;
  --local-registry)
    [[ $# -gt 1 ]] || die "missing value for $1"
    REGISTRY_NAMESPACE="${2%/}"
    shift 2
    ;;
  -v | --variant)
    [[ $# -gt 1 ]] || die "missing value for $1"
    REQUESTED_VARIANTS+=("$2")
    shift 2
    ;;
  --variants)
    [[ $# -gt 1 ]] || die "missing value for $1"
    IFS=',' read -r -a parsed_variants <<<"$2"
    REQUESTED_VARIANTS+=("${parsed_variants[@]}")
    shift 2
    ;;
  -i | --image)
    [[ $# -gt 1 ]] || die "missing value for $1"
    REQUESTED_IMAGES+=("$2")
    shift 2
    ;;
  -f | --force-replace)
    FORCE_REPLACE=true
    shift
    ;;
  --check-remote-digest)
    CHECK_REMOTE_DIGEST=true
    shift
    ;;
  --state-file)
    [[ $# -gt 1 ]] || die "missing value for $1"
    STATE_FILE="$2"
    shift 2
    ;;
  --use-gh-auth-token)
    USE_GH_AUTH_TOKEN=true
    shift
    ;;
  --gh-token)
    [[ $# -gt 1 ]] || die "missing value for $1"
    GH_TOKEN_VALUE="$2"
    shift 2
    ;;
  --gh-username)
    [[ $# -gt 1 ]] || die "missing value for $1"
    GH_USERNAME="$2"
    shift 2
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: $1"
    ;;
  esac
done

REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE%/}"
[[ -n "${REGISTRY_NAMESPACE}" ]] || die "registry namespace cannot be empty"

require_cmd pvesh
require_cmd pvesm

if [[ "${USE_GH_AUTH_TOKEN}" == "true" || "${CHECK_REMOTE_DIGEST}" == "true" || -n "${GH_TOKEN_VALUE}" ]]; then
  require_cmd gh
fi

if [[ "${USE_GH_AUTH_TOKEN}" == "true" ]]; then
  GH_TOKEN_VALUE="$(gh auth token 2>/dev/null || true)"
  [[ -n "${GH_TOKEN_VALUE}" ]] || die "failed to resolve token from gh auth"
fi

if [[ -n "${GH_TOKEN_VALUE}" ]]; then
  export GH_TOKEN="${GH_TOKEN_VALUE}"
  if [[ -z "${GH_USERNAME}" ]]; then
    GH_USERNAME="$(gh api /user -q .login 2>/dev/null || true)"
  fi
  [[ -n "${GH_USERNAME}" ]] || die "failed to resolve GitHub username"
  setup_ghcr_auth "${GH_TOKEN_VALUE}" "${GH_USERNAME}"
fi

if [[ ${#REQUESTED_VARIANTS[@]} -eq 0 && ${#REQUESTED_IMAGES[@]} -eq 0 ]]; then
  if [[ -n "${VARIANTS:-}" ]]; then
    IFS=',' read -r -a REQUESTED_VARIANTS <<<"${VARIANTS}"
  else
    REQUESTED_VARIANTS=("${DEFAULT_VARIANTS[@]}")
  fi
fi

for raw_variant in "${REQUESTED_VARIANTS[@]}"; do
  variant="${raw_variant//[[:space:]]/}"
  [[ -n "${variant}" ]] || continue
  has_variant "${variant}" || die "unsupported variant: ${variant}"
  TARGET_REFERENCES+=("$(build_variant_reference "${variant}")")
  TARGET_FILENAMES+=("$(build_variant_filename "${variant}")")
done

for raw_reference in "${REQUESTED_IMAGES[@]}"; do
  reference="${raw_reference//[[:space:]]/}"
  [[ -n "${reference}" ]] || continue
  TARGET_REFERENCES+=("${reference}")
  TARGET_FILENAMES+=("$(build_image_filename "${reference}")")
done

[[ ${#TARGET_REFERENCES[@]} -gt 0 ]] || die "no targets to pull"

if [[ "${CHECK_REMOTE_DIGEST}" == "true" ]]; then
  if [[ "${REGISTRY_NAMESPACE}" != ghcr.io/* ]]; then
    log "remote digest checks currently support ghcr.io only; skipping digest comparison for registry ${REGISTRY_NAMESPACE}"
    CHECK_REMOTE_DIGEST=false
  fi
  ensure_state_file
fi

pulled_count=0
skipped_count=0

for idx in "${!TARGET_REFERENCES[@]}"; do
  reference="${TARGET_REFERENCES[$idx]}"
  file_name="${TARGET_FILENAMES[$idx]}"
  pull_file_name="$(build_pull_filename "${file_name}")"
  volume_id="${DATASTORE_ID}:vztmpl/${file_name}"
  existing_volume_id=""

  remote_digest=""
  if [[ "${CHECK_REMOTE_DIGEST}" == "true" ]]; then
    remote_digest="$(get_ghcr_digest "${reference}")"
    if [[ -n "${remote_digest}" ]]; then
      log "remote digest ${reference} -> ${remote_digest}"
    else
      log "remote digest unavailable for ${reference}; skipping digest comparison"
    fi
  fi

  replace_existing="${FORCE_REPLACE}"
  if existing_volume_id="$(resolve_existing_volume_id "${volume_id}")"; then
    if [[ "${replace_existing}" != "true" && "${CHECK_REMOTE_DIGEST}" == "true" && -n "${remote_digest}" ]]; then
      stored_digest="$(read_stored_digest "${existing_volume_id}")"
      if [[ -n "${stored_digest}" && "${stored_digest}" == "${remote_digest}" ]]; then
        log "skip ${existing_volume_id} (digest unchanged)"
        skipped_count=$((skipped_count + 1))
        continue
      fi
      replace_existing=true
      if [[ -n "${stored_digest}" ]]; then
        log "digest changed for ${existing_volume_id}: ${stored_digest} -> ${remote_digest}"
      else
        log "no stored digest for ${existing_volume_id}; replacing to sync state"
      fi
    fi

    if [[ "${replace_existing}" == "true" ]]; then
      log "removing existing template ${existing_volume_id}"
      run_cmd pvesm free "${existing_volume_id}"
    else
      log "skip ${existing_volume_id} (already exists)"
      skipped_count=$((skipped_count + 1))
      continue
    fi
  fi

  log "pull ${reference} -> ${file_name}"
  run_cmd pvesh create "/nodes/${NODE_NAME}/storage/${DATASTORE_ID}/oci-registry-pull" \
    --reference "${reference}" \
    --filename "${pull_file_name}"

  if [[ "${CHECK_REMOTE_DIGEST}" == "true" && -n "${remote_digest}" ]]; then
    write_stored_digest "${volume_id}" "${remote_digest}"
  fi

  pulled_count=$((pulled_count + 1))
done

log "done: pulled=${pulled_count} skipped=${skipped_count}"
