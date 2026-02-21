#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  printf "Usage: %s <host> [port] [user]\n" "$0" >&2
  exit 2
fi

host="$1"
port="${2:-22}"
remote_user="${3:-coder}"
export LANG="${LANG:-en_US.UTF-8}"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

workspace="$host"
if [[ "$workspace" == coder.* ]]; then
  workspace="${workspace#coder.}"
fi
if [[ "$workspace" == *.coder ]]; then
  workspace="${workspace%.coder}"
fi

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/hakim-et"
workspace_state_dir="${state_root}/${workspace}"
keys_root="${CODER_ET_KEYS_DIR:-$HOME/.ssh/coder-keys}"
workspace_key_dir="${keys_root}/${workspace}"
host_key_dir="${keys_root}/${host}"
key_ttl_seconds="${CODER_ET_KEY_TTL_SECONDS:-3600}"
startup_timeout_seconds="${CODER_ET_STARTUP_TIMEOUT_SECONDS:-8}"
known_hosts_file="${CODER_ET_KNOWN_HOSTS_FILE:-$HOME/.ssh/coder_known_hosts}"

port_forward_log_file="${workspace_state_dir}/port-forward.log"
port_forward_pid_file="${workspace_state_dir}/port-forward.pid"
et_log_file="${workspace_state_dir}/et.log"
et_pid_file="${workspace_state_dir}/et.pid"
setup_log_file="${workspace_state_dir}/setup.log"
local_key_file="${workspace_key_dir}/id_ed25519"
local_key_pub_file="${local_key_file}.pub"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf "Missing required command: %s\n" "$1" >&2
    exit 1
  fi
}

pid_running() {
  local pid_file="$1"
  local pid

  if [ ! -f "$pid_file" ]; then
    return 1
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -z "$pid" ] || ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  kill -0 "$pid" >/dev/null 2>&1
}

stop_pid_file() {
  local pid_file="$1"
  local pid

  if ! pid_running "$pid_file"; then
    rm -f "$pid_file"
    return
  fi

  pid="$(cat "$pid_file")"
  kill "$pid" >/dev/null 2>&1 || true

  for _ in $(seq 1 10); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi

  rm -f "$pid_file"
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local timeout="$3"

  for _ in $(seq 1 "$timeout"); do
    if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_ssh_banner() {
  local host="$1"
  local port="$2"
  local timeout="$3"
  local line

  for _ in $(seq 1 "$timeout"); do
    if exec 3<>/dev/tcp/"$host"/"$port" 2>/dev/null; then
      IFS= read -r -t 1 line <&3 || true
      exec 3<&-
      exec 3>&-
      if [[ "$line" == SSH-* ]]; then
        return 0
      fi
    fi
    sleep 1
  done

  return 1
}

pid_command_line() {
  local pid_file="$1"
  local pid

  if [ ! -f "$pid_file" ]; then
    return 1
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -z "$pid" ] || ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  ps -p "$pid" -o command= 2>/dev/null || true
}

process_matches() {
  local pid_file="$1"
  local pattern="$2"
  local cmdline

  if ! pid_running "$pid_file"; then
    return 1
  fi

  cmdline="$(pid_command_line "$pid_file")"
  if [ -z "$cmdline" ]; then
    return 1
  fi

  [[ "$cmdline" == *"$pattern"* ]]
}

file_mtime_epoch() {
  local file_path="$1"
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path"
    return
  fi
  stat -c %Y "$file_path"
}

should_rotate_key() {
  if [ ! -f "$local_key_file" ] || [ ! -f "$local_key_pub_file" ]; then
    return 0
  fi

if ! [[ "$key_ttl_seconds" =~ ^[0-9]+$ ]]; then
  return 0
fi

  if [ "$key_ttl_seconds" -eq 0 ]; then
    return 1
  fi

  local now_epoch key_epoch age
  now_epoch="$(date +%s)"
  key_epoch="$(file_mtime_epoch "$local_key_file")"
  age="$((now_epoch - key_epoch))"

  if [ "$age" -ge "$key_ttl_seconds" ]; then
    return 0
  fi

  return 1
}

fallback_to_stdio() {
  if [ -n "${local_workspace_ssh_port:-}" ] && wait_for_ssh_banner 127.0.0.1 "$local_workspace_ssh_port" 1; then
    printf "ET unavailable for workspace %s, falling back to direct forwarded sshd\n" "$workspace" >&2
    exec nc 127.0.0.1 "$local_workspace_ssh_port"
  fi

  if [ -f "$known_hosts_file" ]; then
    ssh-keygen -R "$host" -f "$known_hosts_file" >/dev/null 2>&1 || true
    ssh-keygen -R "coder.${workspace}" -f "$known_hosts_file" >/dev/null 2>&1 || true
    ssh-keygen -R "${workspace}.coder" -f "$known_hosts_file" >/dev/null 2>&1 || true
  fi

  printf "ET unavailable for workspace %s, falling back to coder ssh --stdio\n" "$workspace" >&2
  exec coder ssh --stdio "$workspace"
}

require_command coder
require_command et
require_command nc
require_command ssh-keygen
require_command base64

mkdir -p "$workspace_state_dir"
mkdir -p "$keys_root" "$workspace_key_dir"
chmod 700 "$keys_root" "$workspace_key_dir"

if [ "$host" != "$workspace" ]; then
  mkdir -p "$host_key_dir"
  chmod 700 "$host_key_dir"
fi

hash="$(printf '%s' "$workspace" | cksum | awk '{print $1}')"
offset="$((hash % 2000))"

local_et_port="$((42000 + offset))"
local_workspace_ssh_port="$((44000 + offset))"
local_proxy_ssh_port="$((46000 + offset))"

key_rotated="0"
key_comment_prefix="hakim-et:${workspace}:"

if should_rotate_key; then
  rm -f "$local_key_file" "$local_key_pub_file"
  ssh-keygen -q -t ed25519 -N "" -C "${key_comment_prefix}$(date +%s)" -f "$local_key_file"
  key_rotated="1"
fi
chmod 600 "$local_key_file"
chmod 644 "$local_key_pub_file"

if [ "$host" != "$workspace" ]; then
  if [ -L "${host_key_dir}/id_ed25519" ] || [ -L "${host_key_dir}/id_ed25519.pub" ]; then
    rm -f "${host_key_dir}/id_ed25519" "${host_key_dir}/id_ed25519.pub"
  fi
  if [ ! -f "${host_key_dir}/id_ed25519" ]; then
    install -m 600 "$local_key_file" "${host_key_dir}/id_ed25519"
  fi
  rm -f "${host_key_dir}/id_ed25519.pub"
fi

marker_prefix_b64="$(printf '%s' "$key_comment_prefix" | base64 | tr -d '\n')"
pubkey_b64="$(base64 <"$local_key_pub_file" | tr -d '\n')"
if ! coder ssh "$workspace" -- "set -euo pipefail; umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; marker_prefix=\$(printf '%s' '${marker_prefix_b64}' | base64 -d); pubkey=\$(printf '%s' '${pubkey_b64}' | base64 -d); if ! grep -Fqx \"\$pubkey\" ~/.ssh/authorized_keys; then printf '%s\\n' \"\$pubkey\" >> ~/.ssh/authorized_keys; fi" < /dev/null >"$setup_log_file" 2>&1; then
  printf "coder ssh bootstrap failed for workspace %s\n" "$workspace" >&2
  printf "See log: %s\n" "$setup_log_file" >&2
  exit 1
fi

workspace_host_key_pub="$(coder ssh "$workspace" -- "set -euo pipefail; cat ~/.local/share/hakim-et/ssh_host_ed25519_key.pub" < /dev/null 2>/dev/null || true)"
if [[ "$workspace_host_key_pub" == ssh-ed25519* ]]; then
  host_alias_a="$host"
  host_alias_b="coder.${workspace}"
  host_alias_c="${workspace}.coder"

  mkdir -p "$(dirname "$known_hosts_file")"
  touch "$known_hosts_file"
  chmod 600 "$known_hosts_file"
  ssh-keygen -R "$host_alias_a" -f "$known_hosts_file" >/dev/null 2>&1 || true
  ssh-keygen -R "$host_alias_b" -f "$known_hosts_file" >/dev/null 2>&1 || true
  ssh-keygen -R "$host_alias_c" -f "$known_hosts_file" >/dev/null 2>&1 || true

  printf "%s %s\n" "$host_alias_a" "$workspace_host_key_pub" >>"$known_hosts_file"
  if [ "$host_alias_b" != "$host_alias_a" ]; then
    printf "%s %s\n" "$host_alias_b" "$workspace_host_key_pub" >>"$known_hosts_file"
  fi
  if [ "$host_alias_c" != "$host_alias_a" ] && [ "$host_alias_c" != "$host_alias_b" ]; then
    printf "%s %s\n" "$host_alias_c" "$workspace_host_key_pub" >>"$known_hosts_file"
  fi
fi

if ! pid_running "$port_forward_pid_file" || ! wait_for_tcp 127.0.0.1 "$local_et_port" 1 || ! wait_for_tcp 127.0.0.1 "$local_workspace_ssh_port" 1 || ! wait_for_ssh_banner 127.0.0.1 "$local_workspace_ssh_port" 1; then
  stop_pid_file "$port_forward_pid_file"

  nohup coder port-forward "$workspace" \
    --tcp "127.0.0.1:${local_et_port}:2022" \
    --tcp "127.0.0.1:${local_workspace_ssh_port}:2244" \
    < /dev/null >"$port_forward_log_file" 2>&1 &
  echo "$!" >"$port_forward_pid_file"
fi

if ! process_matches "$port_forward_pid_file" "coder port-forward ${workspace}"; then
  stop_pid_file "$port_forward_pid_file"
  nohup coder port-forward "$workspace" \
    --tcp "127.0.0.1:${local_et_port}:2022" \
    --tcp "127.0.0.1:${local_workspace_ssh_port}:2244" \
    < /dev/null >"$port_forward_log_file" 2>&1 &
  echo "$!" >"$port_forward_pid_file"
fi

if ! [[ "$startup_timeout_seconds" =~ ^[0-9]+$ ]] || [ "$startup_timeout_seconds" -lt 1 ]; then
  startup_timeout_seconds=8
fi

if ! wait_for_tcp 127.0.0.1 "$local_et_port" "$startup_timeout_seconds" || ! wait_for_tcp 127.0.0.1 "$local_workspace_ssh_port" "$startup_timeout_seconds" || ! wait_for_ssh_banner 127.0.0.1 "$local_workspace_ssh_port" "$startup_timeout_seconds"; then
  printf "coder port-forward failed for workspace %s\n" "$workspace" >&2
  printf "See log: %s\n" "$port_forward_log_file" >&2
  fallback_to_stdio
fi

if ! process_matches "$port_forward_pid_file" "coder port-forward ${workspace}"; then
  printf "coder port-forward listener ownership check failed for workspace %s\n" "$workspace" >&2
  printf "See log: %s\n" "$port_forward_log_file" >&2
  fallback_to_stdio
fi

if [ "$key_rotated" = "1" ]; then
  stop_pid_file "$et_pid_file"
fi

if ! pid_running "$et_pid_file" || ! wait_for_tcp 127.0.0.1 "$local_proxy_ssh_port" 1; then
  stop_pid_file "$et_pid_file"

  nohup et -N "${remote_user}@127.0.0.1" \
    -p "${local_et_port}" \
    --ssh-option "Port=${local_workspace_ssh_port}" \
    --ssh-option "SendEnv=LANG" \
    --ssh-option "SendEnv=LC_*" \
    --ssh-option "SendEnv=LANGUAGE" \
    --ssh-option "StrictHostKeyChecking=no" \
    --ssh-option "UserKnownHostsFile=${workspace_state_dir}/known_hosts" \
    --ssh-option "IdentityFile=${local_key_file}" \
    --ssh-option "IdentitiesOnly=yes" \
    -t "${local_proxy_ssh_port}:2244" \
    < /dev/null >"$et_log_file" 2>&1 &
  echo "$!" >"$et_pid_file"
fi

if ! process_matches "$et_pid_file" "${remote_user}@127.0.0.1" || ! process_matches "$et_pid_file" "-p ${local_et_port}"; then
  stop_pid_file "$et_pid_file"
  nohup et -N "${remote_user}@127.0.0.1" \
    -p "${local_et_port}" \
    --ssh-option "Port=${local_workspace_ssh_port}" \
    --ssh-option "SendEnv=LANG" \
    --ssh-option "SendEnv=LC_*" \
    --ssh-option "SendEnv=LANGUAGE" \
    --ssh-option "StrictHostKeyChecking=no" \
    --ssh-option "UserKnownHostsFile=${workspace_state_dir}/known_hosts" \
    --ssh-option "IdentityFile=${local_key_file}" \
    --ssh-option "IdentitiesOnly=yes" \
    -t "${local_proxy_ssh_port}:2244" \
    < /dev/null >"$et_log_file" 2>&1 &
  echo "$!" >"$et_pid_file"
fi

if ! wait_for_tcp 127.0.0.1 "$local_proxy_ssh_port" "$startup_timeout_seconds"; then
  printf "et tunnel failed for workspace %s\n" "$workspace" >&2
  printf "See log: %s\n" "$et_log_file" >&2
  fallback_to_stdio
fi

if ! process_matches "$et_pid_file" "${remote_user}@127.0.0.1" || ! process_matches "$et_pid_file" "-p ${local_et_port}"; then
  printf "et listener ownership check failed for workspace %s\n" "$workspace" >&2
  printf "See log: %s\n" "$et_log_file" >&2
  fallback_to_stdio
fi

exec nc 127.0.0.1 "$local_proxy_ssh_port"
