#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/persistent-volume-lib.sh"

PVE_NODE_NAME="${PVE_NODE_NAME:-}"

if ! command -v pvesm >/dev/null 2>&1 && [[ "${HAKIM_REMOTE_DISPATCH:-}" != "1" ]]; then
  [[ -n "${PVE_NODE_NAME}" ]] || fail "PVE_NODE_NAME is required for remote Proxmox dispatch"
  require_command ssh
  require_command tar
  log "pvesm not found locally; dispatching ensure-home-volume.sh to root@${PVE_NODE_NAME}"
  tar -C "${SCRIPT_DIR}" -cf - persistent-volume-lib.sh ensure-home-volume.sh | ssh \
    "root@${PVE_NODE_NAME}" \
    "set -euo pipefail; workdir=\$(mktemp -d /tmp/hakim-home-volume.XXXXXX); tar -C \"\$workdir\" -xf -; PVE_NODE_NAME='${PVE_NODE_NAME}' PVE_VM_ID='${PVE_VM_ID:-}' PVE_HOME_DATASTORE='${PVE_HOME_DATASTORE:-}' PVE_HOME_VOLUME_ID='${PVE_HOME_VOLUME_ID:-}' HAKIM_OWNER_SLUG='${HAKIM_OWNER_SLUG:-}' HAKIM_WORKSPACE_SLUG='${HAKIM_WORKSPACE_SLUG:-}' HAKIM_HOME_SIZE_GB='${HAKIM_HOME_SIZE_GB:-}' HAKIM_REGISTRY_ROOT='${HAKIM_REGISTRY_ROOT:-}' HAKIM_LEGACY_HOME_ROOT='${HAKIM_LEGACY_HOME_ROOT:-}' HAKIM_HOME_MIGRATION_MODE='${HAKIM_HOME_MIGRATION_MODE:-}' HAKIM_REMOTE_DISPATCH=1 bash \"\$workdir/ensure-home-volume.sh\"; find \"\$workdir\" -mindepth 1 -delete; rmdir \"\$workdir\""
  exit 0
fi

for required in pvesm pct mount umount find grep awk sed mktemp install sync blkid mkfs.ext4; do
  require_command "${required}"
done

PVE_VM_ID="${PVE_VM_ID:?PVE_VM_ID is required}"
PVE_HOME_DATASTORE="${PVE_HOME_DATASTORE:-local-lvm}"
PVE_HOME_VOLUME_ID="${PVE_HOME_VOLUME_ID:-}"
HAKIM_OWNER_SLUG="${HAKIM_OWNER_SLUG:?HAKIM_OWNER_SLUG is required}"
HAKIM_WORKSPACE_SLUG="${HAKIM_WORKSPACE_SLUG:?HAKIM_WORKSPACE_SLUG is required}"
HAKIM_HOME_SIZE_GB="${HAKIM_HOME_SIZE_GB:?HAKIM_HOME_SIZE_GB is required}"
HAKIM_REGISTRY_ROOT="${HAKIM_REGISTRY_ROOT:-/var/lib/hakim/workspace-volumes}"
HAKIM_LEGACY_HOME_ROOT="${HAKIM_LEGACY_HOME_ROOT:-/var/lib/vz/hakim-homes}"
HAKIM_HOME_MIGRATION_MODE="${HAKIM_HOME_MIGRATION_MODE:-copy_keep_source}"

[[ "${PVE_VM_ID}" =~ ^[0-9]+$ ]] || fail "PVE_VM_ID must be numeric"
validate_slug HAKIM_OWNER_SLUG "${HAKIM_OWNER_SLUG}"
validate_slug HAKIM_WORKSPACE_SLUG "${HAKIM_WORKSPACE_SLUG}"
validate_size_gb HAKIM_HOME_SIZE_GB "${HAKIM_HOME_SIZE_GB}"
container_exists "${PVE_VM_ID}" || fail "CT does not exist: ${PVE_VM_ID}"

REGISTRY_DIR="$(registry_dir "${HAKIM_REGISTRY_ROOT}" "${HAKIM_OWNER_SLUG}" "${HAKIM_WORKSPACE_SLUG}")"
LEGACY_HOME_SOURCE="${HAKIM_LEGACY_HOME_ROOT}/${HAKIM_OWNER_SLUG}/${HAKIM_WORKSPACE_SLUG}"

ensure_volume_for_mount \
  home \
  "${REGISTRY_DIR}/home.volume" \
  "${PVE_HOME_DATASTORE}" \
  "${PVE_VM_ID}" \
  "${HAKIM_OWNER_SLUG}" \
  "${HAKIM_WORKSPACE_SLUG}" \
  "${HAKIM_HOME_SIZE_GB}" \
  "${PVE_HOME_VOLUME_ID}" \
  "${LEGACY_HOME_SOURCE}" \
  "${HAKIM_HOME_MIGRATION_MODE}" \
  "${REGISTRY_DIR}" \
  "/home/coder" \
  "mp0" \
  "1"
