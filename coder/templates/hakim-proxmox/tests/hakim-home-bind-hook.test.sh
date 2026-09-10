#!/usr/bin/env bash
set -euo pipefail

template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook_script="${template_dir}/scripts/hakim-home-bind-hook.sh"

run_hook_test() {
  local volume_present="$1"
  local expected_status="$2"
  local temp_dir mock_bin config_root state_root legacy_root call_log output_file
  temp_dir="$(mktemp -d)"
  mock_bin="${temp_dir}/bin"
  config_root="${temp_dir}/etc/pve/lxc"
  state_root="${temp_dir}/state"
  legacy_root="${temp_dir}/legacy"
  call_log="${temp_dir}/calls.log"
  output_file="${temp_dir}/output.log"
  mkdir -p "${mock_bin}" "${config_root}" "${state_root}/shekohex/raptors" "${legacy_root}"
  : >"${call_log}"

  printf '%s\n' 'local-lvm:vm-300-hakim-home-shekohex-raptors' >"${state_root}/shekohex/raptors/home.volume"
  printf '%s\n' 'description: Coder workspace shekohex/raptors hakim_home=enabled,datastore=bG9jYWwtbHZt,owner=shekohex,workspace=raptors,size=128,volume=,migration=copy_keep_source,hook_version=2026-09-10.1' >"${config_root}/300.conf"

  cat >"${mock_bin}/pvesm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pvesm %s\n' "$*" >>"${CALL_LOG}"
if [[ "${1:-}" == "list" ]]; then
  printf '%s\n' 'Volid Format Type Size VMID'
  if [[ "${VOLUME_PRESENT}" == "true" ]]; then
    printf '%s\n' 'local-lvm:vm-300-hakim-home-shekohex-raptors raw rootdir 137438953472 300'
  fi
  exit 0
fi
exit 97
EOF
  chmod +x "${mock_bin}/pvesm"

  cat >"${mock_bin}/pct" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pct %s\n' "$*" >>"${CALL_LOG}"
EOF
  chmod +x "${mock_bin}/pct"

  set +e
  PATH="${mock_bin}:${PATH}" \
    CALL_LOG="${call_log}" \
    VOLUME_PRESENT="${volume_present}" \
    HAKIM_PVE_CONFIG_ROOT="${config_root}" \
    HAKIM_STATE_ROOT="${state_root}" \
    HAKIM_LEGACY_HOME_ROOT="${legacy_root}" \
    bash "${hook_script}" 300 pre-start >"${output_file}" 2>&1
  status=$?
  set -e

  if [[ "${status}" -ne "${expected_status}" ]]; then
    cat "${output_file}" >&2
    printf 'expected status %s, got %s\n' "${expected_status}" "${status}" >&2
    exit 1
  fi

  if grep -Eq '^pvesm (free|alloc|path) ' "${call_log}"; then
    cat "${call_log}" >&2
    printf 'hook called destructive or device-path operation\n' >&2
    exit 1
  fi

  if [[ "${volume_present}" == "true" ]]; then
    grep -q 'local-lvm:vm-300-hakim-home-shekohex-raptors,mp=/home/coder' "${config_root}/300.conf"
  else
    grep -q 'registered home volume .* is missing; refusing to allocate a replacement' "${output_file}"
  fi

  rm -rf "${temp_dir}"
}

run_hook_test true 0
run_hook_test false 1
printf '%s\n' 'hakim-home-bind-hook tests passed'
