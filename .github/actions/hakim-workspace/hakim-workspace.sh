#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
  printf 'command is required\n' >&2
  exit 1
fi
shift || true

log() {
  printf '[hakim-workspace] %s\n' "$*"
}

ensure_tools() {
  for tool in jq tar unzip docker gh mktemp curl find git tr wc; do
    command -v "$tool" >/dev/null 2>&1 || {
      printf 'missing required command: %s\n' "$tool" >&2
      exit 1
    }
  done
}

ensure_age() {
  if command -v age >/dev/null 2>&1; then
    AGE_BIN="$(command -v age)"
    AGE_KEYGEN_BIN="$(command -v age-keygen)"
    export AGE_BIN
    export AGE_KEYGEN_BIN
    return
  fi

  sudo apt-get update >/dev/null
  sudo apt-get install -y age >/dev/null
  AGE_BIN="$(command -v age)"
  AGE_KEYGEN_BIN="$(command -v age-keygen)"
  export AGE_BIN
  export AGE_KEYGEN_BIN
}

init_runtime_context() {
  export WORKSPACE_HOME_DIR="${RUNNER_TEMP}/hakim-home"
  export WORKSPACE_ARTIFACT_NAME="hakim-home-${WORKSPACE_ID}"
  export WORKSPACE_MANIFEST_FILE="${RUNNER_TEMP}/hakim-manifest.json"
  export CONTAINER_NAME="hakim-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
}

append_multiline_env() {
  local name="$1"
  local value="$2"

  {
    printf '%s<<__HAKIM__\n' "$name"
    printf '%s\n' "$value"
    printf '__HAKIM__\n'
  } >> "$GITHUB_ENV"
}

normalize_home_relative_path() {
  local path="$1"

  path="${path%$'\r'}"
  path="${path#~/}"
  path="${path#/home/coder/}"
  path="${path#/}"
  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done

  printf '%s' "$path"
}

normalize_gitignore_pattern() {
  local pattern="$1"
  local negated=''

  pattern="${pattern%$'\r'}"
  if [[ "$pattern" == '!'* ]]; then
    negated='!'
    pattern="${pattern#!}"
  fi

  printf '%s%s' "$negated" "$(normalize_home_relative_path "$pattern")"
}

build_absolute_home_path_list() {
  local raw_paths="$1"
  local raw_path normalized_path result=''

  while IFS= read -r raw_path; do
    raw_path="${raw_path%$'\r'}"
    [[ -n "$raw_path" ]] || continue
    [[ "$raw_path" == '#'* ]] && continue

    normalized_path="$(normalize_home_relative_path "$raw_path")"
    [[ -n "$normalized_path" ]] || continue
    result+="${WORKSPACE_HOME_DIR}/${normalized_path}"$'\n'
  done <<< "$raw_paths"

  printf '%s' "${result%$'\n'}"
}

build_persist_filelist() {
  SNAPSHOT_FILELIST_PATH="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.files"
  local persist_repo persist_excludes_path listing_warnings_path file_count warning_count raw_path normalized_path
  local -a pathspecs git_args

  : > "$SNAPSHOT_FILELIST_PATH"
  SNAPSHOT_FILE_COUNT='0'
  if [[ -z "${WORKSPACE_PERSIST_PATHS:-}" ]]; then
    log 'No persist paths configured; skipping encrypted snapshot.'
    return
  fi

  while IFS= read -r raw_path; do
    raw_path="${raw_path%$'\r'}"
    [[ -n "$raw_path" ]] || continue
    [[ "$raw_path" == '#'* ]] && continue

    normalized_path="$(normalize_home_relative_path "$raw_path")"
    [[ -n "$normalized_path" ]] || continue
    [[ -e "${WORKSPACE_HOME_DIR}/${normalized_path}" ]] || continue
    pathspecs+=("$normalized_path")
  done <<< "$WORKSPACE_PERSIST_PATHS"

  if [[ ${#pathspecs[@]} -eq 0 ]]; then
    log 'Persist paths did not match any files; skipping encrypted snapshot.'
    return
  fi

  persist_repo="$(mktemp -d "${RUNNER_TEMP}/hakim-persist.XXXXXX")"
  persist_excludes_path="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.exclude"
  listing_warnings_path="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.warnings"
  git -C "$persist_repo" init --quiet >/dev/null 2>&1

  git_args=(--git-dir="$persist_repo/.git" --work-tree="$WORKSPACE_HOME_DIR" ls-files -z -co)
  if [[ -n "${WORKSPACE_PERSIST_EXCLUDES:-}" ]]; then
    : > "$persist_excludes_path"
    while IFS= read -r raw_path; do
      raw_path="${raw_path%$'\r'}"
      [[ -n "$raw_path" ]] || continue
      [[ "$raw_path" == '#'* ]] && continue
      printf '%s\n' "$(normalize_gitignore_pattern "$raw_path")" >> "$persist_excludes_path"
    done <<< "$WORKSPACE_PERSIST_EXCLUDES"
    git_args+=(--exclude-from="$persist_excludes_path")
  fi

  git "${git_args[@]}" -- "${pathspecs[@]}" > "$SNAPSHOT_FILELIST_PATH" 2> "$listing_warnings_path"

  rm -rf "$persist_repo"
  rm -f "$persist_excludes_path"

  file_count="$(tr -cd '\0' < "$SNAPSHOT_FILELIST_PATH" | wc -c | tr -d ' ')"
  warning_count="$(wc -l < "$listing_warnings_path" | tr -d ' ')"
  SNAPSHOT_FILE_COUNT="$file_count"
  export SNAPSHOT_FILE_COUNT
  rm -f "$listing_warnings_path"

  if [[ "$warning_count" != '0' ]]; then
    log "Skipped ${warning_count} unreadable paths while building persist file list."
  fi

  log "Prepared persist file list (${file_count} entries)."
}

prepare() {
  ensure_tools
  ensure_age
  init_runtime_context
  log "Preparing workspace ${WORKSPACE_ID}."

  printf '::add-mask::%s\n' "$HAKIM_WORKSPACE_AGE_SECRET_KEY"
  printf '%s' "$HAKIM_WORKSPACE_MANIFEST" > "${RUNNER_TEMP}/hakim-manifest.age"
  "$AGE_BIN" --decrypt --identity <(printf '%s\n' "$HAKIM_WORKSPACE_AGE_SECRET_KEY") --output "$WORKSPACE_MANIFEST_FILE" "${RUNNER_TEMP}/hakim-manifest.age"
  export WORKSPACE_IMAGE="$(jq -r '.workspace_image' "$WORKSPACE_MANIFEST_FILE")"
  export WORKSPACE_OWNER="$(jq -r '.workspace_owner' "$WORKSPACE_MANIFEST_FILE")"
  export PROJECT_DIR="$(jq -r '.project_dir // "/home/coder/project"' "$WORKSPACE_MANIFEST_FILE")"
  export REPO_METADATA_PATH="$(jq -r '.repo_metadata_path // "/home/coder/.local/share/hakim/repo.json"' "$WORKSPACE_MANIFEST_FILE")"
  export GIT_URL_VALUE="$(jq -r '.git_url // ""' "$WORKSPACE_MANIFEST_FILE")"
  export GIT_BRANCH_VALUE="$(jq -r '.git_branch // ""' "$WORKSPACE_MANIFEST_FILE")"
  export WORKSPACE_PERSIST_PATHS="$(jq -r '.persist_paths // ""' "$WORKSPACE_MANIFEST_FILE")"
  export WORKSPACE_PERSIST_EXCLUDES="$(jq -r '.persist_excludes // ""' "$WORKSPACE_MANIFEST_FILE")"
  export WORKSPACE_CACHE_PATHS="$(build_absolute_home_path_list "$(jq -r '.cache_paths // ""' "$WORKSPACE_MANIFEST_FILE")")"
  export WORKSPACE_CACHE_KEY_SEED="$(jq -r '.cache_key_seed // ""' "$WORKSPACE_MANIFEST_FILE")"
  export WORKSPACE_CACHE_PRIMARY_KEY=""
  export WORKSPACE_CACHE_RESTORE_KEY_PREFIX=""
  if [[ -n "$WORKSPACE_CACHE_KEY_SEED" && -n "$WORKSPACE_CACHE_PATHS" ]]; then
    export WORKSPACE_CACHE_PRIMARY_KEY="hakim-cache-${WORKSPACE_ID}-${WORKSPACE_CACHE_KEY_SEED}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
    export WORKSPACE_CACHE_RESTORE_KEY_PREFIX="hakim-cache-${WORKSPACE_ID}-${WORKSPACE_CACHE_KEY_SEED}-"
    while IFS= read -r cache_path; do
      [[ -n "$cache_path" ]] || continue
      if [[ "$cache_path" == */ ]]; then
        mkdir -p "$cache_path"
      else
        mkdir -p "$(dirname "$cache_path")"
      fi
    done <<< "$WORKSPACE_CACHE_PATHS"
  fi
  export CONTAINER_MEMORY_MB="$(jq -r '.container_memory_mb // ""' "$WORKSPACE_MANIFEST_FILE")"
  export CONTAINER_MEMORY_SWAP_MB="$(jq -r '.container_memory_swap_mb // ""' "$WORKSPACE_MANIFEST_FILE")"
  export CONTAINER_CPUS="$(jq -r '.container_cpus // ""' "$WORKSPACE_MANIFEST_FILE")"
  export CODER_AGENT_URL="$(jq -r '.coder_agent_url' "$WORKSPACE_MANIFEST_FILE")"
  export CODER_AGENT_TOKEN="$(jq -r '.coder_agent_token' "$WORKSPACE_MANIFEST_FILE")"
  export WORKSPACE_GITHUB_TOKEN="$(jq -r '.workspace_github_token // ""' "$WORKSPACE_MANIFEST_FILE")"
  export ARTIFACT_AGE_PUBLIC_KEY="$($AGE_KEYGEN_BIN -y <(printf '%s\n' "$HAKIM_WORKSPACE_AGE_SECRET_KEY"))"
  printf '::add-mask::%s\n' "$CODER_AGENT_TOKEN"
  printf '::add-mask::%s\n' "$WORKSPACE_GITHUB_TOKEN"
  {
    printf 'WORKSPACE_HOME_DIR=%s\n' "$WORKSPACE_HOME_DIR"
    printf 'WORKSPACE_ARTIFACT_NAME=%s\n' "$WORKSPACE_ARTIFACT_NAME"
    printf 'WORKSPACE_MANIFEST_FILE=%s\n' "$WORKSPACE_MANIFEST_FILE"
    printf 'CONTAINER_NAME=%s\n' "$CONTAINER_NAME"
    printf 'WORKSPACE_IMAGE=%s\n' "$WORKSPACE_IMAGE"
    printf 'WORKSPACE_OWNER=%s\n' "$WORKSPACE_OWNER"
    printf 'PROJECT_DIR=%s\n' "$PROJECT_DIR"
    printf 'REPO_METADATA_PATH=%s\n' "$REPO_METADATA_PATH"
    printf 'GIT_URL_VALUE=%s\n' "$GIT_URL_VALUE"
    printf 'GIT_BRANCH_VALUE=%s\n' "$GIT_BRANCH_VALUE"
    printf 'CONTAINER_MEMORY_MB=%s\n' "$CONTAINER_MEMORY_MB"
    printf 'CONTAINER_MEMORY_SWAP_MB=%s\n' "$CONTAINER_MEMORY_SWAP_MB"
    printf 'CONTAINER_CPUS=%s\n' "$CONTAINER_CPUS"
    printf 'CODER_AGENT_URL=%s\n' "$CODER_AGENT_URL"
    printf 'CODER_AGENT_TOKEN=%s\n' "$CODER_AGENT_TOKEN"
    printf 'WORKSPACE_GITHUB_TOKEN=%s\n' "$WORKSPACE_GITHUB_TOKEN"
    printf 'ARTIFACT_AGE_PUBLIC_KEY=%s\n' "$ARTIFACT_AGE_PUBLIC_KEY"
    printf 'WORKSPACE_CACHE_PRIMARY_KEY=%s\n' "$WORKSPACE_CACHE_PRIMARY_KEY"
    printf 'WORKSPACE_CACHE_RESTORE_KEY_PREFIX=%s\n' "$WORKSPACE_CACHE_RESTORE_KEY_PREFIX"
  } >> "$GITHUB_ENV"
  append_multiline_env 'WORKSPACE_PERSIST_PATHS' "$WORKSPACE_PERSIST_PATHS"
  append_multiline_env 'WORKSPACE_PERSIST_EXCLUDES' "$WORKSPACE_PERSIST_EXCLUDES"
  append_multiline_env 'WORKSPACE_CACHE_PATHS' "$WORKSPACE_CACHE_PATHS"
  log "Prepared manifest and runtime metadata for ${WORKSPACE_ID}."
}

restore() {
  ensure_tools
  ensure_age
  init_runtime_context
  mkdir -p "$WORKSPACE_HOME_DIR"

  artifact_id="$(GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts?per_page=100" --jq '.artifacts | map(select(.name == "'"${WORKSPACE_ARTIFACT_NAME}"'" and .expired == false)) | sort_by(.created_at) | reverse | .[0].id // empty')"
  if [[ -z "$artifact_id" ]]; then
    log "No snapshot artifact found for ${WORKSPACE_ARTIFACT_NAME}; starting fresh."
    exit 0
  fi

  archive_zip="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.zip"
  download_dir="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}-download"
  rm -rf "$download_dir"
  mkdir -p "$download_dir"
  GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts/${artifact_id}/zip" > "$archive_zip"
  unzip -qo "$archive_zip" -d "$download_dir"
  encrypted_archive="$(find "$download_dir" -type f -name '*.age' | sed -n '1p')"
  if [[ -z "$encrypted_archive" ]]; then
    log "Artifact ${artifact_id} did not contain an encrypted snapshot; starting fresh."
    exit 0
  fi

  tarball="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.tar.gz"
  "$AGE_BIN" --decrypt --identity <(printf '%s\n' "$HAKIM_WORKSPACE_AGE_SECRET_KEY") --output "$tarball" "$encrypted_archive"
  tar -xzf "$tarball" -C "$WORKSPACE_HOME_DIR"
  log "Restored snapshot artifact ${artifact_id} into ${WORKSPACE_HOME_DIR}."
}

run_workspace() {
  ensure_tools
  init_runtime_context
  docker pull "$WORKSPACE_IMAGE" >/dev/null
  docker_args=()
  if [[ -n "${CONTAINER_MEMORY_MB:-}" && "${CONTAINER_MEMORY_MB}" != '0' ]]; then
    docker_args+=(--memory "${CONTAINER_MEMORY_MB}m")
  fi
  if [[ -n "${CONTAINER_MEMORY_SWAP_MB:-}" && "${CONTAINER_MEMORY_SWAP_MB}" != '0' ]]; then
    docker_args+=(--memory-swap "${CONTAINER_MEMORY_SWAP_MB}m")
  fi
  if [[ -n "${CONTAINER_CPUS:-}" && "${CONTAINER_CPUS}" != '0' ]]; then
    docker_args+=(--cpus "$CONTAINER_CPUS")
  fi

  cleanup_container() {
    docker stop --time 30 "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker wait "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  }

  trap 'cleanup_container; trap - TERM INT HUP; exit 0' TERM INT HUP

  docker run -d \
    --name "$CONTAINER_NAME" \
    --hostname "$WORKSPACE_NAME" \
    --add-host host.docker.internal:host-gateway \
    --shm-size 1g \
    "${docker_args[@]}" \
    -v "$WORKSPACE_HOME_DIR:/home/coder" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e CODER_AGENT_URL="$CODER_AGENT_URL" \
    -e CODER_AGENT_TOKEN="$CODER_AGENT_TOKEN" \
    -e CODER_PROJECT_DIR=/home/coder/project \
    -e GH_TOKEN="$WORKSPACE_GITHUB_TOKEN" \
    -e GITHUB_TOKEN="$WORKSPACE_GITHUB_TOKEN" \
    -e GITHUB_ACTIONS=true \
    -e GITHUB_REPOSITORY="$GITHUB_REPOSITORY" \
    -e GITHUB_RUN_ID="$GITHUB_RUN_ID" \
    -e GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT" \
    -e GITHUB_RUN_NUMBER="$GITHUB_RUN_NUMBER" \
    -e GITHUB_WORKFLOW="$GITHUB_WORKFLOW" \
    -e GITHUB_ACTOR="$GITHUB_ACTOR" \
    -e GITHUB_SERVER_URL="$GITHUB_SERVER_URL" \
    -e GITHUB_API_URL="$GITHUB_API_URL" \
    -e HAKIM_CONTROL_REPOSITORY="$GITHUB_REPOSITORY" \
    -e HAKIM_CONTROL_RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" \
    -e HAKIM_WORKSPACE_ID="$WORKSPACE_ID" \
    -e HAKIM_WORKSPACE_NAME="$WORKSPACE_NAME" \
    -e HAKIM_WORKSPACE_OWNER="$WORKSPACE_OWNER" \
    -e HAKIM_WORKSPACE_ARTIFACT_NAME="$WORKSPACE_ARTIFACT_NAME" \
    -e HAKIM_WORKSPACE_TIMEOUT_SECONDS="$HAKIM_WORKSPACE_MAX_RUNTIME_SECONDS" \
    -e HAKIM_PROJECT_DIR="$PROJECT_DIR" \
    -e HAKIM_REPO_METADATA_FILE="$REPO_METADATA_PATH" \
    -e HAKIM_GIT_URL="$GIT_URL_VALUE" \
    -e HAKIM_GIT_BRANCH="$GIT_BRANCH_VALUE" \
    -e HAKIM_AUTO_YIELD_ON_IDLE=1 \
    -e START_DOCKER_DAEMON=0 \
    "$WORKSPACE_IMAGE" >/dev/null

  start_epoch="$(date +%s)"
  max_runtime_seconds="${HAKIM_WORKSPACE_MAX_RUNTIME_SECONDS:-21000}"
  log "Started container ${CONTAINER_NAME} from ${WORKSPACE_IMAGE} with ${max_runtime_seconds}s runtime budget."

  while true; do
    container_status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || printf 'missing')"
    if [[ "$container_status" != 'running' ]]; then
      exit_code="$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER_NAME" 2>/dev/null || printf '1')"
      cleanup_container
      trap - TERM INT HUP
      if [[ "$exit_code" == '0' ]]; then
        log "Container ${CONTAINER_NAME} exited cleanly."
        exit 0
      fi
      log "Container ${CONTAINER_NAME} exited with code ${exit_code}."
      exit "$exit_code"
    fi

    now_epoch="$(date +%s)"
    if (( now_epoch - start_epoch >= max_runtime_seconds )); then
      log "Runtime budget reached; shutting down container ${CONTAINER_NAME}."
      cleanup_container
      trap - TERM INT HUP
      exit 0
    fi

    sleep 15
  done
}

snapshot() {
  ensure_tools
  ensure_age
  init_runtime_context
  if [[ ! -d "$WORKSPACE_HOME_DIR" ]]; then
    log "Workspace home ${WORKSPACE_HOME_DIR} is missing; skipping snapshot."
    exit 0
  fi
  if [[ -z "${ARTIFACT_AGE_PUBLIC_KEY:-}" ]]; then
    log "Snapshot encryption key is unavailable; skipping snapshot."
    exit 0
  fi

  encrypted_path="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.tar.gz.age"
  build_persist_filelist
  if [[ "${SNAPSHOT_FILE_COUNT:-0}" == '0' ]]; then
    rm -f "$SNAPSHOT_FILELIST_PATH"
    log 'No matching persist files found; skipping encrypted snapshot.'
    exit 0
  fi
  printf '%s\n' "$ARTIFACT_AGE_PUBLIC_KEY" > "${RUNNER_TEMP}/hakim-age.pub"
  tar --null --no-recursion --ignore-failed-read -czf - -C "$WORKSPACE_HOME_DIR" -T "$SNAPSHOT_FILELIST_PATH" | "$AGE_BIN" --encrypt --recipients-file "${RUNNER_TEMP}/hakim-age.pub" --output "$encrypted_path"
  rm -f "$SNAPSHOT_FILELIST_PATH"
  printf 'WORKSPACE_SNAPSHOT_PATH=%s\n' "$encrypted_path" >> "$GITHUB_ENV"
  log "Created encrypted snapshot ${encrypted_path}."
}

cleanup() {
  init_runtime_context

  artifacts_json="$(GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts?per_page=100")"
  printf '%s' "$artifacts_json" | jq -r '.artifacts | map(select(.name == "'"${WORKSPACE_ARTIFACT_NAME}"'" and .expired == false)) | sort_by(.created_at) | reverse | .[3:] | .[].id' | while read -r artifact_id; do
    [[ -n "$artifact_id" ]] || continue
    GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api -X DELETE "repos/${GITHUB_REPOSITORY}/actions/artifacts/${artifact_id}" >/dev/null 2>&1 || true
  done
  log "Cleaned workflow metadata for ${WORKSPACE_ID}."
}

case "$command_name" in
  prepare) prepare ;;
  restore) restore ;;
  run) run_workspace ;;
  snapshot) snapshot ;;
  cleanup) cleanup ;;
  *) printf 'unknown command: %s\n' "$command_name" >&2; exit 1 ;;
esac
