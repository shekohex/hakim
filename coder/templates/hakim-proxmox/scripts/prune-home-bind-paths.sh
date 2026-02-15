#!/usr/bin/env bash
set -euo pipefail

for required in pct sed awk; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

BASE_PATH="${1:-/var/lib/hakim/workspace-homes}"
MODE="${2:---dry-run}"

if [[ ! -d "${BASE_PATH}" ]]; then
  printf 'base path does not exist: %s\n' "${BASE_PATH}"
  exit 0
fi

declare -A referenced_paths=()

while read -r ctid; do
  [[ -n "${ctid}" ]] || continue
  home_source="$(pct config "${ctid}" | sed -n 's/^mp[0-9]\+: \([^,]*\),.*mp=\/home\/coder.*/\1/p' | sed -n '1p')"
  if [[ -n "${home_source}" && "${home_source}" == "${BASE_PATH}"/* ]]; then
    referenced_paths["${home_source}"]=1
  fi
done < <(pct list | sed '1d' | awk '{print $1}')

stale_count=0
for dir in "${BASE_PATH}"/*; do
  [[ -d "${dir}" ]] || continue
  if [[ -z "${referenced_paths[${dir}]+x}" ]]; then
    printf 'stale: %s\n' "${dir}"
    stale_count=$((stale_count + 1))
    if [[ "${MODE}" == "--apply" ]]; then
      rm -rf -- "${dir}"
      printf 'deleted: %s\n' "${dir}"
    fi
  fi
done

if [[ "${MODE}" != "--apply" ]]; then
  printf 'dry-run complete, stale paths: %d\n' "${stale_count}"
else
  printf 'apply complete, removed paths: %d\n' "${stale_count}"
fi
