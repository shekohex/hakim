#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/persistent-volume-lib.sh"

PVE_NODE_NAME="${PVE_NODE_NAME:-}"
PVE_SSH_HOST="${PVE_SSH_HOST:-${PVE_NODE_NAME}}"

if ! command -v pct >/dev/null 2>&1 && [[ "${HAKIM_REMOTE_DISPATCH:-}" != "1" ]]; then
  [[ -n "${PVE_SSH_HOST}" ]] || fail "PVE_SSH_HOST or PVE_NODE_NAME is required for remote Proxmox dispatch"
  require_command ssh
  require_command tar
  log "pct not found locally; dispatching detach-home-volume.sh to root@${PVE_SSH_HOST}"
  tar -C "${SCRIPT_DIR}" -cf - persistent-volume-lib.sh detach-home-volume.sh | ssh \
    "root@${PVE_SSH_HOST}" \
    "set -euo pipefail; workdir=\$(mktemp -d /tmp/hakim-home-volume.XXXXXX); tar -C \"\$workdir\" -xf -; PVE_NODE_NAME='${PVE_NODE_NAME}' PVE_VM_ID='${PVE_VM_ID:-}' HAKIM_OWNER_SLUG='${HAKIM_OWNER_SLUG:-}' HAKIM_WORKSPACE_SLUG='${HAKIM_WORKSPACE_SLUG:-}' HAKIM_REGISTRY_ROOT='${HAKIM_REGISTRY_ROOT:-}' HAKIM_REMOTE_DISPATCH=1 bash \"\$workdir/detach-home-volume.sh\"; find \"\$workdir\" -mindepth 1 -delete; rmdir \"\$workdir\""
  exit 0
fi

require_command pct
require_command awk

PVE_VM_ID="${PVE_VM_ID:?PVE_VM_ID is required}"
[[ "${PVE_VM_ID}" =~ ^[0-9]+$ ]] || fail "PVE_VM_ID must be numeric"

detach_mount_path "${PVE_VM_ID}" "/home/coder"
