#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[hakim-persistent-volume] %s\n' "$*" >&2
}

fail() {
  printf '[hakim-persistent-volume] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || fail "missing required command: ${command_name}"
}

validate_slug() {
  local name="$1"
  local value="$2"
  [[ -n "${value}" ]] || fail "${name} is required"
  [[ "${value}" != *"/"* && "${value}" != *".."* ]] || fail "${name} contains unsafe path characters: ${value}"
}

validate_size_gb() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[0-9]+$ && "${value}" -gt 0 ]] || fail "${name} must be a positive integer"
}

registry_dir() {
  printf '%s/%s/%s' "$1" "$2" "$3"
}

atomic_write_file() {
  local path="$1"
  local value="$2"
  local directory temporary
  directory="$(dirname "${path}")"
  install -d -m 0755 "${directory}"
  temporary="$(mktemp "${directory}/.tmp.XXXXXX")"
  printf '%s\n' "${value}" >"${temporary}"
  sync "${temporary}" 2>/dev/null || sync
  mv "${temporary}" "${path}"
}

path_is_non_empty_dir() {
  local path="$1"
  [[ -d "${path}" ]] || return 1
  find "${path}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
}

volume_exists() {
  local volume_id="$1"
  pvesm path "${volume_id}" >/dev/null 2>&1
}

volume_path() {
  local volume_id="$1"
  pvesm path "${volume_id}"
}

allocate_volume() {
  local datastore="$1"
  local vm_id="$2"
  local name="$3"
  local size_gb="$4"
  local output volume_id

  log "allocating ${datastore} volume ${name} size=${size_gb}G for CT ${vm_id}"
  if volume_exists "${datastore}:${name}"; then
    log "volume already exists from previous attempt, reusing unregistered volume ${datastore}:${name}"
    printf '%s' "${datastore}:${name}"
    return 0
  fi
  output="$(pvesm alloc "${datastore}" "${vm_id}" "${name}" "${size_gb}G" 2>&1)" || fail "pvesm alloc failed: ${output}"
  volume_id="$(printf '%s\n' "${output}" | sed -n 's/.*successfully created volume '\''\([^'\'']*\)'\''.*/\1/p' | tail -n 1)"
  if [[ -z "${volume_id}" ]]; then
    volume_id="$(printf '%s\n' "${output}" | grep -Eo "${datastore}:[^[:space:]]+" | tail -n 1 || true)"
  fi
  volume_id="${volume_id%\'}"
  volume_id="${volume_id#\'}"
  [[ -n "${volume_id}" ]] || fail "could not determine allocated volume id from pvesm output: ${output}"
  volume_exists "${volume_id}" || fail "allocated volume does not resolve via pvesm path: ${volume_id}"
  printf '%s' "${volume_id}"
}

mount_volume_temporarily() {
  local volume_id="$1"
  local mount_dir="$2"
  local path
  path="$(volume_path "${volume_id}")"
  install -d -m 0755 "${mount_dir}"
  if mountpoint -q "${path}"; then
    mount --bind "${path}" "${mount_dir}"
  else
    if command -v blkid >/dev/null 2>&1 && ! blkid "${path}" >/dev/null 2>&1; then
      require_command mkfs.ext4
      log "formatting new volume ${volume_id} as ext4"
      mkfs.ext4 -F "${path}" >/dev/null
    fi
    mount "${path}" "${mount_dir}"
  fi
}

copy_tree_keep_source() {
  local source="$1"
  local target="$2"

  if command -v rsync >/dev/null 2>&1; then
    log "copying ${source} to ${target} with rsync; source stays untouched"
    rsync -aHAX --numeric-ids "${source}/" "${target}/"
  else
    log "copying ${source} to ${target} with cp -a fallback; source stays untouched"
    cp -a "${source}/." "${target}/"
  fi
  sync
}

container_exists() {
  local vm_id="$1"
  pct config "${vm_id}" >/dev/null 2>&1
}

container_running() {
  local vm_id="$1"
  [[ "$(pct status "${vm_id}" 2>/dev/null | awk '{print $2}')" == "running" ]]
}

stop_container_if_running() {
  local vm_id="$1"
  if container_running "${vm_id}"; then
    log "stopping CT ${vm_id} before mount config change"
    pct stop "${vm_id}"
    printf 'true'
  else
    printf 'false'
  fi
}

start_container_if_needed() {
  local vm_id="$1"
  local should_start="$2"
  if [[ "${should_start}" == "true" ]]; then
    log "starting CT ${vm_id} after mount config change"
    pct start "${vm_id}"
  fi
}

mount_key_for_path() {
  local vm_id="$1"
  local mount_path="$2"
  pct config "${vm_id}" | awk -v path="mp=${mount_path}" '/^mp[0-9]+:/ && index($0, path) { sub(":", "", $1); print $1; exit }'
}

mount_entry_for_key() {
  local vm_id="$1"
  local key="$2"
  pct config "${vm_id}" | awk -v key="${key}:" '$1 == key { sub(/^[^:]+: /, ""); print; exit }'
}

next_mount_key() {
  local vm_id="$1"
  local preferred="$2"
  local index key
  if ! pct config "${vm_id}" | grep -q "^${preferred}:"; then
    printf '%s' "${preferred}"
    return 0
  fi
  for index in $(seq 0 255); do
    key="mp${index}"
    if ! pct config "${vm_id}" | grep -q "^${key}:"; then
      printf '%s' "${key}"
      return 0
    fi
  done
  fail "no free mount point key for CT ${vm_id}"
}

attach_mount() {
  local vm_id="$1"
  local source="$2"
  local mount_path="$3"
  local preferred_key="$4"
  local backup="$5"
  local existing_key existing_entry existing_source mount_key

  existing_key="$(mount_key_for_path "${vm_id}" "${mount_path}")"
  if [[ -n "${existing_key}" ]]; then
    existing_entry="$(mount_entry_for_key "${vm_id}" "${existing_key}")"
    existing_source="${existing_entry%%,*}"
    if [[ "${existing_source}" == "${source}" ]]; then
      log "CT ${vm_id} already has ${mount_path} mounted from ${source}"
      return 0
    fi
    fail "CT ${vm_id} ${mount_path} already mounted from ${existing_source}, refusing to overwrite with ${source}"
  fi

  mount_key="$(next_mount_key "${vm_id}" "${preferred_key}")"
  log "attaching ${source} to CT ${vm_id} at ${mount_path} as ${mount_key}"
  pct set "${vm_id}" -"${mount_key}" "${source},mp=${mount_path},backup=${backup}"
}

detach_mount_if_source_matches() {
  local vm_id="$1"
  local mount_path="$2"
  local expected_source="$3"
  local key entry current_source

  key="$(mount_key_for_path "${vm_id}" "${mount_path}")"
  if [[ -z "${key}" ]]; then
    return 0
  fi

  entry="$(mount_entry_for_key "${vm_id}" "${key}")"
  current_source="${entry%%,*}"
  if [[ "${current_source}" != "${expected_source}" ]]; then
    return 1
  fi

  log "detaching legacy ${mount_path} mount from ${expected_source} before attaching migrated volume"
  pct set "${vm_id}" -delete "${key}"
}

detach_mount_path() {
  local vm_id="$1"
  local mount_path="$2"
  local key was_running
  if ! container_exists "${vm_id}"; then
    log "CT ${vm_id} does not exist; detach skipped"
    return 0
  fi
  key="$(mount_key_for_path "${vm_id}" "${mount_path}")"
  if [[ -z "${key}" ]]; then
    log "CT ${vm_id} has no mount at ${mount_path}; detach skipped"
    return 0
  fi
  log "detaching ${mount_path} from CT ${vm_id} by deleting ${key}; backing data stays"
  was_running="$(stop_container_if_running "${vm_id}")"
  pct set "${vm_id}" -delete "${key}"
  start_container_if_needed "${vm_id}" "${was_running}"
}

ensure_volume_for_mount() {
  local kind="$1"
  local registry_file="$2"
  local datastore="$3"
  local vm_id="$4"
  local owner_slug="$5"
  local workspace_slug="$6"
  local size_gb="$7"
  local explicit_source="$8"
  local source_path="$9"
  local migration_mode="${10}"
  local registry_directory="${11}"
  local mount_path="${12}"
  local preferred_key="${13}"
  local backup="${14}"
  local migration_status_file source_path_file volume_id volume_name temp_mount was_running

  migration_status_file="${registry_directory}/${kind}.migration-status"
  source_path_file="${registry_directory}/${kind}.source-path"

  if [[ -n "${explicit_source}" ]]; then
    if [[ "${explicit_source}" == /* ]]; then
      [[ -d "${explicit_source}" ]] || install -d -m 0777 "${explicit_source}"
      volume_id="${explicit_source}"
      backup=0
      log "using explicit bind source for ${kind}: ${volume_id}; migration skipped"
    else
      volume_exists "${explicit_source}" || fail "explicit ${kind} volume does not exist: ${explicit_source}"
      volume_id="${explicit_source}"
      log "using explicit Proxmox volume for ${kind}: ${volume_id}; migration skipped"
    fi
  elif [[ -f "${registry_file}" ]]; then
    volume_id="$(tr -d '\r\n' <"${registry_file}")"
    [[ -n "${volume_id}" ]] || fail "registry file is empty: ${registry_file}"
    volume_exists "${volume_id}" || fail "registry says ${kind} volume exists but Proxmox volume is missing: ${volume_id}"
    log "reusing registered ${kind} volume: ${volume_id}"
  else
    if [[ "${migration_mode}" == "disabled" && -d "${source_path}" ]]; then
      fail "legacy ${kind} source exists and migration is disabled: ${source_path}"
    fi
    if [[ "${migration_mode}" == "fail_if_legacy_source_exists" && -d "${source_path}" ]]; then
      fail "legacy ${kind} source exists: ${source_path}"
    fi
    [[ "${migration_mode}" == "copy_keep_source" || "${migration_mode}" == "disabled" || "${migration_mode}" == "fail_if_legacy_source_exists" ]] || fail "unsupported ${kind} migration mode: ${migration_mode}"

    volume_name="vm-${vm_id}-hakim-${kind}-${owner_slug}-${workspace_slug}"
    volume_name="$(printf '%s' "${volume_name}" | tr -c 'A-Za-z0-9_.-' '-')"
    volume_id="$(allocate_volume "${datastore}" "${vm_id}" "${volume_name}" "${size_gb}")"
    temp_mount="$(mktemp -d "/tmp/hakim-${kind}.XXXXXX")"
    cleanup_mount() {
      if mountpoint -q "${temp_mount}"; then
        umount "${temp_mount}"
      fi
      rmdir "${temp_mount}" 2>/dev/null || true
    }
    trap cleanup_mount EXIT
    mount_volume_temporarily "${volume_id}" "${temp_mount}"
    if path_is_non_empty_dir "${source_path}"; then
      copy_tree_keep_source "${source_path}" "${temp_mount}"
      atomic_write_file "${source_path_file}" "${source_path}"
      atomic_write_file "${migration_status_file}" "copied_keep_source"
      log "${kind} migration copied; source kept at ${source_path}"
    else
      atomic_write_file "${migration_status_file}" "new_empty_volume"
      log "${kind} initialized as empty volume"
    fi
    sync
    cleanup_mount
    trap - EXIT
    atomic_write_file "${registry_file}" "${volume_id}"
    log "registered ${kind} volume: ${volume_id}"
  fi

  was_running="$(stop_container_if_running "${vm_id}")"
  if [[ "${explicit_source}" == "" && "${volume_id}" != "${source_path}" && -n "${source_path}" ]]; then
    detach_mount_if_source_matches "${vm_id}" "${mount_path}" "${source_path}" || true
  fi
  attach_mount "${vm_id}" "${volume_id}" "${mount_path}" "${preferred_key}" "${backup}"
  start_container_if_needed "${vm_id}" "${was_running}"
}
