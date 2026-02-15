#!/usr/bin/env bash
set -euo pipefail

for required in pvesm pct sed awk; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

DATASTORE="${1:-}"
CTID="${2:-}"
MODE="${3:---dry-run}"

if [[ -z "${DATASTORE}" || -z "${CTID}" ]]; then
  printf 'usage: %s <datastore> <ctid> [--dry-run|--apply]\n' "${0}" >&2
  exit 1
fi

if [[ ! "${CTID}" =~ ^[0-9]+$ ]]; then
  printf 'ctid must be numeric\n' >&2
  exit 1
fi

if [[ "${MODE}" != "--dry-run" && "${MODE}" != "--apply" ]]; then
  printf 'mode must be --dry-run or --apply\n' >&2
  exit 1
fi

declare -A referenced_volumes=()

while read -r other_ctid; do
  [[ -n "${other_ctid}" ]] || continue
  while read -r volume; do
    [[ -n "${volume}" ]] || continue
    referenced_volumes["${volume}"]=1
  done < <(pct config "${other_ctid}" | sed -n "s/^[a-z0-9]\+: \(${DATASTORE}:[^,]*\).*/\1/p")
done < <(pct list | sed '1d' | awk '{print $1}')

removed=0
while read -r volume; do
  [[ -n "${volume}" ]] || continue
  if [[ -n "${referenced_volumes[${volume}]+x}" ]]; then
    continue
  fi

  printf 'stale: %s\n' "${volume}"
  removed=$((removed + 1))

  if [[ "${MODE}" == "--apply" ]]; then
    pvesm free "${volume}"
    printf 'deleted: %s\n' "${volume}"
  fi
done < <(pvesm list "${DATASTORE}" | sed '1d' | awk '{print $1}' | awk -v ds="${DATASTORE}" -v ctid="${CTID}" '$0 ~ "^" ds ":(vm|subvol)-" ctid "-disk-[0-9]+$" { print }')

if [[ "${MODE}" == "--dry-run" ]]; then
  printf 'dry-run complete, stale volumes: %d\n' "${removed}"
else
  printf 'apply complete, removed volumes: %d\n' "${removed}"
fi
