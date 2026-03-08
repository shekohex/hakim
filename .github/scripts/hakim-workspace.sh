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

signal_name() {
  local prefix="$1"
  local workspace_id_upper
  workspace_id_upper="${WORKSPACE_ID^^}"
  workspace_id_upper="${workspace_id_upper//-/_}"
  printf '%s_%s\n' "$prefix" "$workspace_id_upper"
}

delete_variable() {
  local name="$1"
  GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api -X DELETE "repos/${GITHUB_REPOSITORY}/actions/variables/${name}" >/dev/null 2>&1 || true
}

set_variable() {
  local name="$1"
  local value="$2"
  if GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api "repos/${GITHUB_REPOSITORY}/actions/variables/${name}" >/dev/null 2>&1; then
    GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api -X PATCH "repos/${GITHUB_REPOSITORY}/actions/variables/${name}" -f name="$name" -f value="$value" >/dev/null
  else
    GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api -X POST "repos/${GITHUB_REPOSITORY}/actions/variables" -f name="$name" -f value="$value" >/dev/null
  fi
}

build_snapshot_filelist() {
  SNAPSHOT_FILELIST_PATH="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.files"
  local ageignore_path file_count

  ageignore_path="${WORKSPACE_HOME_DIR}/.ageignore"
  (
    cd "$WORKSPACE_HOME_DIR"
    while IFS= read -r -d '' path; do
      path="${path#./}"
      if [[ -f "$ageignore_path" ]] && git -c core.excludesFile="$ageignore_path" check-ignore --no-index --quiet "$path"; then
        continue
      fi
      printf '%s\0' "$path"
    done < <(find . -mindepth 1 -print0)
  ) > "$SNAPSHOT_FILELIST_PATH"

  file_count="$(tr -cd '\0' < "$SNAPSHOT_FILELIST_PATH" | wc -c | tr -d ' ')"
  if [[ -f "$ageignore_path" ]]; then
    log "Prepared snapshot file list (${file_count} entries) using ${ageignore_path}."
  else
    log "Prepared snapshot file list (${file_count} entries) without .ageignore overrides."
  fi
}

prepare() {
  ensure_tools
  ensure_age
  log "Preparing workspace ${WORKSPACE_ID}."

  export STOP_SIGNAL_NAME="$(signal_name HAKIM_STOP)"
  export RUN_SIGNAL_NAME="$(signal_name HAKIM_RUN)"
  export WORKSPACE_HOME_DIR="${RUNNER_TEMP}/hakim-home"
  export WORKSPACE_ARTIFACT_NAME="hakim-home-${WORKSPACE_ID}"
  export WORKSPACE_MANIFEST_FILE="${RUNNER_TEMP}/hakim-manifest.json"
  export CONTAINER_NAME="hakim-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"

  delete_variable "$STOP_SIGNAL_NAME"
  set_variable "$RUN_SIGNAL_NAME" "$GITHUB_RUN_ID"

  printf '::add-mask::%s\n' "$HAKIM_WORKSPACE_AGE_SECRET_KEY"
  printf '%s' "$HAKIM_WORKSPACE_MANIFEST" > "${RUNNER_TEMP}/hakim-manifest.age"
  "$AGE_BIN" --decrypt --identity <(printf '%s\n' "$HAKIM_WORKSPACE_AGE_SECRET_KEY") --output "$WORKSPACE_MANIFEST_FILE" "${RUNNER_TEMP}/hakim-manifest.age"
  export WORKSPACE_IMAGE="$(jq -r '.workspace_image' "$WORKSPACE_MANIFEST_FILE")"
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
    printf 'STOP_SIGNAL_NAME=%s\n' "$STOP_SIGNAL_NAME"
    printf 'RUN_SIGNAL_NAME=%s\n' "$RUN_SIGNAL_NAME"
    printf 'WORKSPACE_HOME_DIR=%s\n' "$WORKSPACE_HOME_DIR"
    printf 'WORKSPACE_ARTIFACT_NAME=%s\n' "$WORKSPACE_ARTIFACT_NAME"
    printf 'WORKSPACE_MANIFEST_FILE=%s\n' "$WORKSPACE_MANIFEST_FILE"
    printf 'CONTAINER_NAME=%s\n' "$CONTAINER_NAME"
    printf 'WORKSPACE_IMAGE=%s\n' "$WORKSPACE_IMAGE"
    printf 'CONTAINER_MEMORY_MB=%s\n' "$CONTAINER_MEMORY_MB"
    printf 'CONTAINER_MEMORY_SWAP_MB=%s\n' "$CONTAINER_MEMORY_SWAP_MB"
    printf 'CONTAINER_CPUS=%s\n' "$CONTAINER_CPUS"
    printf 'CODER_AGENT_URL=%s\n' "$CODER_AGENT_URL"
    printf 'CODER_AGENT_TOKEN=%s\n' "$CODER_AGENT_TOKEN"
    printf 'WORKSPACE_GITHUB_TOKEN=%s\n' "$WORKSPACE_GITHUB_TOKEN"
    printf 'ARTIFACT_AGE_PUBLIC_KEY=%s\n' "$ARTIFACT_AGE_PUBLIC_KEY"
  } >> "$GITHUB_ENV"
  log "Prepared manifest and runtime metadata for ${WORKSPACE_ID}."
}

restore() {
  ensure_tools
  ensure_age
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

  trap 'cleanup_container; exit 1' TERM INT HUP

  docker run -d \
    --name "$CONTAINER_NAME" \
    --hostname "$WORKSPACE_NAME" \
    --add-host host.docker.internal:host-gateway \
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
    -e HAKIM_WORKSPACE_ARTIFACT_NAME="$WORKSPACE_ARTIFACT_NAME" \
    -e HAKIM_WORKSPACE_TIMEOUT_SECONDS="$HAKIM_WORKSPACE_MAX_RUNTIME_SECONDS" \
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

    if GH_TOKEN="$HAKIM_CONTROL_GH_TOKEN" gh api "repos/${GITHUB_REPOSITORY}/actions/variables/${STOP_SIGNAL_NAME}" >/dev/null 2>&1; then
      log "Stop signal ${STOP_SIGNAL_NAME} received; shutting down container ${CONTAINER_NAME}."
      cleanup_container
      trap - TERM INT HUP
      exit 0
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
  if [[ ! -d "$WORKSPACE_HOME_DIR" ]]; then
    log "Workspace home ${WORKSPACE_HOME_DIR} is missing; skipping snapshot."
    exit 0
  fi

  archive_path="${RUNNER_TEMP}/${WORKSPACE_ARTIFACT_NAME}.tar.gz"
  encrypted_path="${archive_path}.age"
  build_snapshot_filelist
  tar --null -czf "$archive_path" -C "$WORKSPACE_HOME_DIR" -T "$SNAPSHOT_FILELIST_PATH"
  printf '%s\n' "$ARTIFACT_AGE_PUBLIC_KEY" > "${RUNNER_TEMP}/hakim-age.pub"
  "$AGE_BIN" --encrypt --recipient-file "${RUNNER_TEMP}/hakim-age.pub" --output "$encrypted_path" "$archive_path"
  rm -f "$archive_path"
  printf 'WORKSPACE_SNAPSHOT_PATH=%s\n' "$encrypted_path" >> "$GITHUB_ENV"
  log "Created encrypted snapshot ${encrypted_path}."
}

cleanup() {
  delete_variable "$STOP_SIGNAL_NAME"
  delete_variable "$RUN_SIGNAL_NAME"

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
