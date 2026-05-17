#!/bin/bash
set -euo pipefail

HOOK_VERSION="2026-05-17.3"

VMID="${1:-}"
PHASE="${2:-}"

if [[ -z "${VMID}" || "${PHASE}" != "pre-start" ]]; then
  exit 0
fi

config_file="/etc/pve/lxc/${VMID}.conf"
if [[ ! -f "${config_file}" ]]; then
  exit 0
fi

log() {
  printf '[hakim-home-hook] %s\n' "$*" >&2
}

decode_base64() {
  printf '%s' "$1" | base64 -d 2>/dev/null || true
}

config_value() {
  local key="$1"
  sed -n "s/^${key}: //p" "${config_file}" | tail -n 1
}

delete_mount_config() {
  local mount_key="$1"
  local temp_config
  temp_config="$(mktemp)"
  grep -v "^${mount_key}: " "${config_file}" >"${temp_config}"
  cp "${temp_config}" "${config_file}"
  rm -f "${temp_config}"
}

set_mount_config() {
  local mount_key="$1"
  local mount_value="$2"
  local temp_config
  temp_config="$(mktemp)"
  grep -v "^${mount_key}: " "${config_file}" >"${temp_config}"
  printf '%s: %s\n' "${mount_key}" "${mount_value}" >>"${temp_config}"
  cp "${temp_config}" "${config_file}"
  rm -f "${temp_config}"
}

resize_home_volume_if_needed() {
  local mount_key="$1"
  local requested_size_gb="$2"

  if [[ -z "${mount_key}" || ! "${requested_size_gb}" =~ ^[0-9]+$ || "${requested_size_gb}" -le 0 ]]; then
    return
  fi

  local existing_entry existing_size_gb
  existing_entry="$(sed -n "s/^${mount_key}: //p" "${config_file}")"
  existing_size_gb="$(printf '%s' "${existing_entry}" | sed -n 's/.*size=\([0-9]\+\)G.*/\1/p')"

  if [[ -n "${existing_size_gb}" && "${existing_size_gb}" =~ ^[0-9]+$ && "${existing_size_gb}" -ge "${requested_size_gb}" ]]; then
    return
  fi

  log "growing ${mount_key} home volume to ${requested_size_gb}G"
  pct resize "${VMID}" "${mount_key}" "${requested_size_gb}G" >/dev/null
}

description="$(config_value description)"
if [[ -z "${description}" ]]; then
  description="$(sed -n 's/^#//p' "${config_file}" | head -n 1)"
fi
home_spec="$(printf '%s' "${description}" | sed -n 's/.*hakim_home=\([^ ]*\).*/\1/p')"

if [[ -n "${home_spec}" ]]; then
  declare -A spec=()
  IFS=',' read -ra pairs <<<"${home_spec}"
  for pair in "${pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    spec["${key}"]="${value}"
  done

  if [[ "${spec[enabled]:-}" == "enabled" ]]; then
    datastore="$(decode_base64 "${spec[datastore]:-}")"
    owner_slug="${spec[owner]:-}"
    workspace_slug="${spec[workspace]:-}"
    size_gb="${spec[size]:-}"
    explicit_source="$(decode_base64 "${spec[volume]:-}")"
    migration_mode="${spec[migration]:-copy_keep_source}"
    expected_hook_version="${spec[hook_version]:-}"
    registry_dir="/var/lib/hakim/workspace-volumes/${owner_slug}/${workspace_slug}"
    registry_file="${registry_dir}/home.volume"
    migration_status_file="${registry_dir}/home.migration-status"
    source_path_file="${registry_dir}/home.source-path"
    legacy_source="/var/lib/vz/hakim-homes/${owner_slug}/${workspace_slug}"

    [[ -n "${datastore}" ]] || datastore="local-lvm"

    if [[ -n "${expected_hook_version}" && "${HOOK_VERSION}" != "${expected_hook_version}" ]]; then
      log "host hook version ${HOOK_VERSION} does not match template hook version ${expected_hook_version}; update ${0}"
      exit 1
    fi

    if [[ -n "${explicit_source}" ]]; then
      volume_id="${explicit_source}"
      if [[ "${volume_id}" == /* ]]; then
        install -d -m 0777 "${volume_id}"
        chown 100000:100000 "${volume_id}"
        chmod 0777 "${volume_id}"
        backup="0"
      else
        pvesm path "${volume_id}" >/dev/null
        backup="1"
      fi
    elif [[ -f "${registry_file}" ]]; then
      volume_id="$(tr -d '\r\n' <"${registry_file}")"
      pvesm path "${volume_id}" >/dev/null
      backup="1"
    else
      [[ "${size_gb}" =~ ^[0-9]+$ && "${size_gb}" -gt 0 ]] || size_gb="30"
      if [[ "${migration_mode}" == "disabled" && -d "${legacy_source}" ]]; then
        log "legacy home source exists and migration is disabled: ${legacy_source}"
        exit 1
      fi
      if [[ "${migration_mode}" == "fail_if_legacy_source_exists" && -d "${legacy_source}" ]]; then
        log "legacy home source exists: ${legacy_source}"
        exit 1
      fi
      if [[ "${migration_mode}" != "copy_keep_source" && "${migration_mode}" != "disabled" && "${migration_mode}" != "fail_if_legacy_source_exists" ]]; then
        log "unsupported home migration mode: ${migration_mode}"
        exit 1
      fi

      volume_name="vm-${VMID}-hakim-home-${owner_slug}-${workspace_slug}"
      volume_name="$(printf '%s' "${volume_name}" | tr -c 'A-Za-z0-9_.-' '-')"
      volume_id="${datastore}:${volume_name}"
      if ! pvesm path "${volume_id}" >/dev/null 2>&1 || [[ ! -e "$(pvesm path "${volume_id}" 2>/dev/null || true)" ]]; then
        log "allocating ${volume_id} size=${size_gb}G"
        pvesm free "${volume_id}" >/dev/null 2>&1 || true
        pvesm alloc "${datastore}" "${VMID}" "${volume_name}" "${size_gb}G" >/dev/null
      fi

      volume_path="$(pvesm path "${volume_id}")"
      if ! blkid "${volume_path}" >/dev/null 2>&1; then
        log "formatting ${volume_id} as ext4"
        mkfs.ext4 -F "${volume_path}" >/dev/null
      fi

      temp_mount="$(mktemp -d /tmp/hakim-home.XXXXXX)"
      cleanup_temp_mount() {
        if mountpoint -q "${temp_mount}"; then
          umount "${temp_mount}"
        fi
        rmdir "${temp_mount}" 2>/dev/null || true
      }
      trap cleanup_temp_mount EXIT
      mount "${volume_path}" "${temp_mount}"

      if [[ -d "${legacy_source}" ]] && find "${legacy_source}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        log "copying legacy home ${legacy_source} to ${volume_id}; source stays untouched"
        if command -v rsync >/dev/null 2>&1; then
          rsync -aHAX --numeric-ids --exclude='/.local/share/docker' --exclude='/.local/share/docker.old' "${legacy_source}/" "${temp_mount}/"
        else
          tar --exclude='./.local/share/docker' --exclude='./.local/share/docker.old' -C "${legacy_source}" -cf - . | tar -C "${temp_mount}" -xf -
        fi
        install -d -m 0755 "${registry_dir}"
        printf '%s\n' "${legacy_source}" >"${source_path_file}"
        printf '%s\n' "copied_keep_source" >"${migration_status_file}"
      else
        install -d -m 0755 "${registry_dir}"
        printf '%s\n' "new_empty_volume" >"${migration_status_file}"
      fi
      sync
      cleanup_temp_mount
      trap - EXIT
      printf '%s\n' "${volume_id}" >"${registry_file}"
      backup="1"
    fi

    existing_key="$(sed -n '/^mp[0-9]\+: /p' "${config_file}" | awk 'index($0, "mp=/home/coder,") || $0 ~ /mp=\/home\/coder$/ { sub(":", "", $1); print $1; exit }')"
    if [[ -n "${existing_key}" ]]; then
      existing_entry="$(sed -n "s/^${existing_key}: //p" "${config_file}")"
      existing_source="${existing_entry%%,*}"
      if [[ "${existing_source}" != "${volume_id}" ]]; then
        if [[ "${existing_source}" == "${legacy_source}" ]]; then
          log "detaching legacy home mount ${legacy_source}"
          delete_mount_config "${existing_key}"
          existing_key=""
        else
          log "/home/coder already mounted from ${existing_source}; refusing to replace with ${volume_id}"
          exit 1
        fi
      elif [[ "${volume_id}" != /* ]]; then
        resize_home_volume_if_needed "${existing_key}" "${size_gb}"
      fi
    fi

    if [[ -z "${existing_key}" ]]; then
      target_key="mp0"
      if grep -q '^mp0: ' "${config_file}"; then
        for index in $(seq 0 255); do
          if ! grep -q "^mp${index}: " "${config_file}"; then
            target_key="mp${index}"
            break
          fi
        done
      fi
      log "attaching ${volume_id} to /home/coder as ${target_key}"
      set_mount_config "${target_key}" "${volume_id},mp=/home/coder,backup=${backup}"
      if [[ "${volume_id}" != /* ]]; then
        resize_home_volume_if_needed "${target_key}" "${size_gb}"
      fi
    fi
  fi
fi

while IFS= read -r line; do
  source_spec="${line#*: }"
  source_path="${source_spec%%,*}"
  mount_path="$(printf '%s' "${source_spec}" | sed -n 's/.*mp=\([^,]*\).*/\1/p')"

  if [[ "${source_path}" != /* ]]; then
    continue
  fi

  if [[ "${mount_path}" != "/home/coder" && "${mount_path}" != "/home/coder/.local/share/docker" ]]; then
    continue
  fi

  install -d -m 0777 "${source_path}"
  chown 100000:100000 "${source_path}"
  chmod 0777 "${source_path}"
done < <(sed -n '/^mp[0-9]\+: /p' "${config_file}")
