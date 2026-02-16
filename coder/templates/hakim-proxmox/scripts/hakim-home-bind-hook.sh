#!/bin/bash
set -euo pipefail

VMID="${1:-}"
PHASE="${2:-}"

if [[ -z "${VMID}" || "${PHASE}" != "pre-start" ]]; then
  exit 0
fi

line="$(pct config "${VMID}" | sed -n '/^mp[0-9]\+: .*mp=\/home\/coder\(,\|$\)/{p;q;}')"
if [[ -z "${line}" ]]; then
  exit 0
fi

source_spec="${line#*: }"
source_path="${source_spec%%,*}"

if [[ "${source_path}" != /* ]]; then
  exit 0
fi

install -d -m 0777 "${source_path}"
chmod 0777 "${source_path}"
