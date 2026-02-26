#!/bin/bash
set -euo pipefail

VMID="${1:-}"
PHASE="${2:-}"

if [[ -z "${VMID}" || "${PHASE}" != "pre-start" ]]; then
  exit 0
fi

config_file="/etc/pve/lxc/${VMID}.conf"
if [[ ! -f "${config_file}" ]]; then
  exit 0
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
