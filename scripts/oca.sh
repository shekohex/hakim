#!/usr/bin/env bash
set -euo pipefail

readonly OCA_REMOTE_HOME="${OCA_REMOTE_HOME:-/home/coder}"
readonly OCA_REMOTE_PROJECT_DIR="${OCA_REMOTE_PROJECT_DIR:-/home/coder/project}"
readonly OCA_REMOTE_OPENCODE_PORT="${OCA_REMOTE_OPENCODE_PORT:-4096}"
readonly OCA_STARTUP_TIMEOUT_SECONDS="${OCA_STARTUP_TIMEOUT_SECONDS:-60}"
readonly OCA_PORT_RETRY_COUNT="${OCA_PORT_RETRY_COUNT:-10}"

VERBOSE="0"
LOCAL_PORT=""
PORT_FORWARD_PID=""
STATE_DIR=""
PORT_FORWARD_LOG_FILE=""

print_help() {
  cat <<EOF
Usage:
  oca list [coder list args...]
  oca doctor [workspace]
  oca status <workspace>
  oca <workspace> [--dir <dir>] [--tcp <spec> ...] [opencode attach args...]
  oca <workspace> [--dir <dir>] [--tcp <spec> ...] run [opencode run args...]

Commands:
  list              Run coder list.
  doctor            Check local prerequisites, Coder auth, and optional workspace reachability.
  status            Show workspace details and OpenCode health.
  run               Run opencode run --attach against the workspace server.

Options:
  --dir <dir>       Remote directory for context. Absolute paths stay absolute,
                    ~/ expands to ${OCA_REMOTE_HOME}, and relative paths are
                    resolved from ${OCA_REMOTE_PROJECT_DIR}.
  --tcp <spec>      Extra TCP forward, same syntax as coder port-forward --tcp.
  --verbose         Print wrapper steps and keep temp logs/state.
  -h, --help        Show this help.

Examples:
  oca list
  oca doctor
  oca doctor my-workspace
  oca status my-workspace
  oca my-workspace
  oca my-workspace --dir api
  oca my-workspace --dir ~/project/foo --tcp 3000:3000
  oca my-workspace --dir services/api run "fix the failing tests"
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

log() {
  if [ "$VERBOSE" = "1" ]; then
    printf 'oca: %s\n' "$*" >&2
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Missing required command: $1"
  fi
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

first_line() {
  local text="$1"
  printf '%s\n' "${text%%$'\n'*}"
}

print_check() {
  local label="$1"
  local status="$2"
  local detail="$3"
  printf '%-14s %-4s %s\n' "$label" "$status" "$detail"
}

create_temp_dir() {
  local dir

  if dir="$(mktemp -d 2>/dev/null)"; then
    printf '%s\n' "$dir"
    return 0
  fi

  mktemp -d -t oca
}

stop_port_forward() {
  if [ -n "$PORT_FORWARD_PID" ] && kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi

  PORT_FORWARD_PID=""
}

cleanup() {
  local exit_code="$?"

  stop_port_forward

  if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ]; then
    if [ "$VERBOSE" = "1" ] || [ "$exit_code" -ne 0 ]; then
      printf 'oca: state kept at %s\n' "$STATE_DIR" >&2
    else
      rm -rf "$STATE_DIR"
    fi
  fi
}

normalize_posix_path() {
  local input="$1"
  local absolute="0"
  local result=""
  local part
  local -a parts=()
  local -a stack=()

  if [[ "$input" == /* ]]; then
    absolute="1"
  fi

  IFS='/' read -r -a parts <<<"$input"

  for part in "${parts[@]}"; do
    case "$part" in
      ""|".")
        ;;
      "..")
        if [ "${#stack[@]}" -gt 0 ]; then
          unset "stack[${#stack[@]}-1]"
        fi
        ;;
      *)
        stack+=("$part")
        ;;
    esac
  done

  if [ "$absolute" = "1" ]; then
    result="/"
  fi

  for part in "${stack[@]}"; do
    if [ -z "$result" ] || [ "$result" = "/" ]; then
      result="${result}${part}"
    else
      result="${result}/$part"
    fi
  done

  if [ -z "$result" ]; then
    if [ "$absolute" = "1" ]; then
      result="/"
    else
      result="."
    fi
  fi

  printf '%s\n' "$result"
}

normalize_remote_dir() {
  local raw="${1:-.}"
  local expanded

  case "$raw" in
    ""|".")
      expanded="$OCA_REMOTE_PROJECT_DIR"
      ;;
    \~)
      expanded="$OCA_REMOTE_HOME"
      ;;
    \~/*)
      expanded="${OCA_REMOTE_HOME}/${raw#~/}"
      ;;
    /*)
      expanded="$raw"
      ;;
    *)
      expanded="${OCA_REMOTE_PROJECT_DIR}/${raw}"
      ;;
  esac

  normalize_posix_path "$expanded"
}

random_local_port() {
  printf '%s\n' "$((49152 + (RANDOM % 16384)))"
}

wait_for_opencode_health() {
  local port="$1"
  local url="http://127.0.0.1:${port}/global/health"
  local attempt=1

  while [ "$attempt" -le "$OCA_STARTUP_TIMEOUT_SECONDS" ]; do
    if curl -fsS --max-time 1 "$url" >/dev/null 2>&1; then
      return 0
    fi

    if ! kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1; then
      return 1
    fi

    sleep 1
    attempt=$((attempt + 1))
  done

  return 2
}

start_port_forward() {
  local workspace="$1"
  shift
  local attempt=1
  local local_port=""
  local status=1
  local -a tcp_specs=("$@")
  local -a command_args=()

  while [ "$attempt" -le "$OCA_PORT_RETRY_COUNT" ]; do
    local_port="$(random_local_port)"
    command_args=(port-forward "$workspace" --tcp "127.0.0.1:${local_port}:${OCA_REMOTE_OPENCODE_PORT}")
    log "starting port-forward attempt ${attempt}/${OCA_PORT_RETRY_COUNT} for ${workspace} on 127.0.0.1:${local_port} -> ${OCA_REMOTE_OPENCODE_PORT}"

    if [ "${#tcp_specs[@]}" -gt 0 ]; then
      local spec
      for spec in "${tcp_specs[@]}"; do
        command_args+=(--tcp "$spec")
      done
    fi

    : >"$PORT_FORWARD_LOG_FILE"
    coder --no-version-warning "${command_args[@]}" < /dev/null >"$PORT_FORWARD_LOG_FILE" 2>&1 &
    PORT_FORWARD_PID="$!"
    log "port-forward pid ${PORT_FORWARD_PID}; log ${PORT_FORWARD_LOG_FILE}"

    if wait_for_opencode_health "$local_port"; then
      LOCAL_PORT="$local_port"
      log "opencode health ready at http://127.0.0.1:${LOCAL_PORT}"
      return 0
    fi

    status="$?"
    stop_port_forward

    if [ "$status" -eq 2 ]; then
      log "timed out waiting for opencode health on http://127.0.0.1:${local_port}"
      break
    fi

    log "port-forward exited before readiness; retrying"

    attempt=$((attempt + 1))
  done

  printf 'Failed to start coder port-forward for workspace %s\n' "$workspace" >&2
  if [ -f "$PORT_FORWARD_LOG_FILE" ]; then
    printf 'Last log file: %s\n' "$PORT_FORWARD_LOG_FILE" >&2
  fi
  return 1
}

validate_mode_args() {
  local mode="$1"
  shift
  local arg

  for arg in "$@"; do
    case "$arg" in
      --dir|--dir=*)
        die "Use wrapper --dir before the workspace command."
        ;;
      --attach|--attach=*)
        if [ "$mode" = "run" ]; then
          die "Do not pass --attach to opencode run; oca sets it automatically."
        fi
        ;;
    esac
  done
}

run_attach() {
  local url="$1"
  local remote_dir="$2"
  shift 2

  opencode attach "$url" --dir "$remote_dir" "$@"
}

run_remote() {
  local url="$1"
  local remote_dir="$2"
  shift 2

  opencode run --attach "$url" --dir "$remote_dir" "$@"
}

run_doctor() {
  local workspace="${1:-}"
  local output=""
  local status_line=""
  local failures=0

  if command_available coder; then
    output="$(coder version 2>/dev/null || true)"
    print_check "coder" "ok" "$(first_line "$output")"
  else
    print_check "coder" "fail" "not found"
    failures=$((failures + 1))
  fi

  if command_available opencode; then
    output="$(opencode --version 2>/dev/null || true)"
    print_check "opencode" "ok" "$(first_line "$output")"
  else
    print_check "opencode" "fail" "not found"
    failures=$((failures + 1))
  fi

  if command_available curl; then
    output="$(curl --version 2>/dev/null || true)"
    print_check "curl" "ok" "$(first_line "$output")"
  else
    print_check "curl" "fail" "not found"
    failures=$((failures + 1))
  fi

  if ! command_available coder; then
    return 1
  fi

  if output="$(coder --no-version-warning whoami 2>&1)"; then
    status_line="authenticated"
    if [ -n "$output" ]; then
      status_line="$(first_line "$output")"
    fi
    print_check "coder auth" "ok" "$status_line"
  else
    print_check "coder auth" "fail" "$(first_line "$output")"
    failures=$((failures + 1))
  fi

  if [ -n "$workspace" ]; then
    if output="$(coder --no-version-warning show "$workspace" 2>&1)"; then
      print_check "workspace" "ok" "$workspace"
    else
      print_check "workspace" "fail" "$(first_line "$output")"
      failures=$((failures + 1))
      return "$failures"
    fi

    if [ "$failures" -eq 0 ]; then
      STATE_DIR="$(create_temp_dir)"
      PORT_FORWARD_LOG_FILE="${STATE_DIR}/port-forward.log"
      trap cleanup EXIT INT TERM
      if start_port_forward "$workspace"; then
        print_check "opencode" "ok" "http://127.0.0.1:${LOCAL_PORT}/global/health"
      else
        print_check "opencode" "fail" "port-forward or healthcheck failed"
        failures=$((failures + 1))
      fi
    fi
  fi

  [ "$failures" -eq 0 ]
}

run_status() {
  local workspace="$1"

  require_command coder
  require_command curl

  printf 'Workspace\n'
  coder --no-version-warning show "$workspace"

  STATE_DIR="$(create_temp_dir)"
  PORT_FORWARD_LOG_FILE="${STATE_DIR}/port-forward.log"
  trap cleanup EXIT INT TERM
  start_port_forward "$workspace"

  printf '\nOpenCode\n'
  printf 'health: ok\n'
  printf 'attach: http://127.0.0.1:%s\n' "$LOCAL_PORT"
  printf 'default dir: %s\n' "$(normalize_remote_dir .)"
}

main() {
  local workspace=""
  local mode="attach"
  local remote_dir_raw="."
  local remote_dir=""
  local arg
  local list_arg
  local -a tcp_specs=()
  local -a list_args=()
  local -a pending_args=()
  local -a mode_args=()

  if [ "$#" -eq 0 ]; then
    print_help
    exit 1
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --verbose)
        VERBOSE="1"
        shift
        ;;
      -h|--help|help)
        print_help
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  [ "$#" -gt 0 ] || {
    print_help
    exit 1
  }

  if [ "$1" = "list" ]; then
    require_command coder
    shift
    while [ "$#" -gt 0 ]; do
      list_arg="$1"
      case "$list_arg" in
        --verbose)
          VERBOSE="1"
          shift
          ;;
        *)
          list_args+=("$list_arg")
          shift
          ;;
      esac
    done
    log "running coder list"
    exec coder --no-version-warning list "${list_args[@]}"
  fi

  if [ "$1" = "doctor" ]; then
    shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --verbose)
          VERBOSE="1"
          shift
          ;;
        -h|--help)
          print_help
          exit 0
          ;;
        *)
          break
          ;;
      esac
    done

    if [ "$#" -gt 1 ]; then
      die "Usage: oca doctor [workspace]"
    fi

    run_doctor "${1:-}"
    return $?
  fi

  if [ "$1" = "status" ]; then
    shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --verbose)
          VERBOSE="1"
          shift
          ;;
        -h|--help)
          print_help
          exit 0
          ;;
        *)
          break
          ;;
      esac
    done

    [ "$#" -ge 1 ] || die "Usage: oca status <workspace>"
    [ "$#" -le 1 ] || die "Usage: oca status <workspace>"
    run_status "$1"
    return 0
  fi

  require_command coder
  require_command opencode
  require_command curl

  workspace="$1"
  shift

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -h|--help)
        print_help
        exit 0
        ;;
      --dir)
        [ "$#" -ge 2 ] || die "Missing value for --dir"
        remote_dir_raw="$2"
        shift 2
        ;;
      --dir=*)
        remote_dir_raw="${arg#*=}"
        shift
        ;;
      --tcp)
        [ "$#" -ge 2 ] || die "Missing value for --tcp"
        tcp_specs+=("$2")
        shift 2
        ;;
      --tcp=*)
        tcp_specs+=("${arg#*=}")
        shift
        ;;
      --verbose)
        VERBOSE="1"
        shift
        ;;
      run)
        mode="run"
        shift
        mode_args=("${pending_args[@]}" "$@")
        break
        ;;
      --)
        shift
        pending_args+=("$@")
        break
        ;;
      *)
        pending_args+=("$arg")
        shift
        ;;
    esac
  done

  if [ "$mode" = "attach" ]; then
    mode_args=("${pending_args[@]}")
  fi

  validate_mode_args "$mode" "${mode_args[@]}"

  remote_dir="$(normalize_remote_dir "$remote_dir_raw")"
  log "workspace ${workspace}"
  log "mode ${mode}"
  log "remote dir ${remote_dir}"
  STATE_DIR="$(create_temp_dir)"
  PORT_FORWARD_LOG_FILE="${STATE_DIR}/port-forward.log"
  trap cleanup EXIT INT TERM

  start_port_forward "$workspace" "${tcp_specs[@]}"

  if [ "$mode" = "run" ]; then
    log "running opencode run against http://127.0.0.1:${LOCAL_PORT}"
    run_remote "http://127.0.0.1:${LOCAL_PORT}" "$remote_dir" "${mode_args[@]}"
    return 0
  fi

  log "running opencode attach against http://127.0.0.1:${LOCAL_PORT}"
  run_attach "http://127.0.0.1:${LOCAL_PORT}" "$remote_dir" "${mode_args[@]}"
}

main "$@"
