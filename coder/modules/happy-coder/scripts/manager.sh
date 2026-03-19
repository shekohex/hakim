#!/bin/bash
set -euo pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

expand_home() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${1#~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

resolve_home_dir() {
  if [ -n "${HAPPY_HOME_DIR:-}" ]; then
    expand_home "$HAPPY_HOME_DIR"
    return 0
  fi

  if [ -n "${HAPPY_OPENCODE_HOME_DEFAULT:-}" ]; then
    expand_home "$HAPPY_OPENCODE_HOME_DEFAULT"
    return 0
  fi

  printf '%s/.happy\n' "$HOME"
}

state_root() {
  printf '%s/hakim/opencode\n' "$(resolve_home_dir)"
}

default_port() {
  if [ -n "${HAPPY_OPENCODE_PORT:-}" ]; then
    printf '%s\n' "$HAPPY_OPENCODE_PORT"
    return 0
  fi

  if [ -n "${HAPPY_OPENCODE_PORT_DEFAULT:-}" ]; then
    printf '%s\n' "$HAPPY_OPENCODE_PORT_DEFAULT"
    return 0
  fi

  printf '4096\n'
}

hash_string() {
  if command_exists shasum; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    return 0
  fi

  if command_exists sha256sum; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
    return 0
  fi

  printf '%s' "$1" | cksum | awk '{print $1}'
}

resolve_cwd() {
  local raw="${1:-.}"

  if [ -d "$raw" ]; then
    (
      cd "$raw"
      pwd -P
    )
    return 0
  fi

  printf 'ERROR: directory not found: %s\n' "$raw" >&2
  exit 1
}

state_dir_for_cwd() {
  local cwd="$1"
  printf '%s/%s\n' "$(state_root)" "$(hash_string "$cwd")"
}

state_file_path() {
  local cwd="$1"
  printf '%s/state.env\n' "$(state_dir_for_cwd "$cwd")"
}

log_file_path() {
  local cwd="$1"
  printf '%s/session.log\n' "$(state_dir_for_cwd "$cwd")"
}

load_state() {
  local cwd="$1"
  local state_file

  STATE_PID=""
  STATE_SESSION_ID=""
  STATE_URL=""
  STATE_CWD="$cwd"
  STATE_LOG_FILE="$(log_file_path "$cwd")"

  state_file="$(state_file_path "$cwd")"
  if [ -f "$state_file" ]; then
    . "$state_file"
    STATE_PID="${PID:-}"
    STATE_SESSION_ID="${SESSION_ID:-}"
    STATE_URL="${URL:-}"
    STATE_CWD="${CWD:-$cwd}"
    STATE_LOG_FILE="${LOG_FILE:-$STATE_LOG_FILE}"
  fi
}

save_state() {
  local cwd="$1"
  local state_dir
  local state_file

  state_dir="$(state_dir_for_cwd "$cwd")"
  state_file="$(state_file_path "$cwd")"
  mkdir -p "$state_dir"

  {
    printf 'PID=%q\n' "$STATE_PID"
    printf 'SESSION_ID=%q\n' "$STATE_SESSION_ID"
    printf 'URL=%q\n' "$STATE_URL"
    printf 'CWD=%q\n' "$STATE_CWD"
    printf 'LOG_FILE=%q\n' "$STATE_LOG_FILE"
  } > "$state_file"
}

clear_state() {
  local cwd="$1"
  rm -rf "$(state_dir_for_cwd "$cwd")"
}

process_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null
}

extract_session_id() {
  local log_file="$1"

  if [ ! -f "$log_file" ]; then
    return 1
  fi

  sed -n 's/.*Happy Session ID: //p' "$log_file" | head -n 1
}

wait_for_session_id() {
  local pid="$1"
  local log_file="$2"
  local attempts=60
  local attempt=1
  local session_id=""

  while [ "$attempt" -le "$attempts" ]; do
    session_id="$(extract_session_id "$log_file" || true)"
    if [ -n "$session_id" ]; then
      printf '%s\n' "$session_id"
      return 0
    fi

    if ! process_running "$pid"; then
      break
    fi

    sleep 1
    attempt=$((attempt + 1))
  done

  return 1
}

ensure_command() {
  if ! command_exists "$1"; then
    printf 'ERROR: missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

opencode_url_for_port() {
  printf 'http://localhost:%s\n' "$1"
}

opencode_healthcheck() {
  local url="$1"
  curl -fsS "$url/global/health" > /dev/null 2>&1
}

print_usage() {
  cat <<EOF
Usage:
  happy-opencode [command] [--cwd <dir>] [--port <port>] [--url <url>]

Commands:
  start     Start a Happy ACP session for the current directory in background
  stop      Stop the Happy ACP session for the current directory
  restart   Restart the Happy ACP session for the current directory
  status    Show status for the current directory
  logs      Print the log path for the current directory
  list      List sessions tracked by the Happy daemon

Examples:
  happy-opencode
  happy-opencode start
  happy-opencode stop
  happy-opencode restart --port 4096
  happy-opencode status --cwd ~/project/api
EOF
}

list_sessions() {
  happy daemon list
}

start_session() {
  local cwd="$1"
  local url="$2"
  local state_dir

  load_state "$cwd"
  if process_running "$STATE_PID"; then
    printf 'Happy ACP already running for %s\n' "$cwd"
    if [ -n "$STATE_SESSION_ID" ]; then
      printf 'Happy Session ID: %s\n' "$STATE_SESSION_ID"
    fi
    printf 'PID: %s\n' "$STATE_PID"
    printf 'Logs: %s\n' "$STATE_LOG_FILE"
    return 0
  fi

  ensure_command happy
  ensure_command curl

  if ! opencode_healthcheck "$url"; then
    printf 'ERROR: OpenCode server is not reachable at %s\n' "$url" >&2
    exit 1
  fi

  state_dir="$(state_dir_for_cwd "$cwd")"
  mkdir -p "$state_dir"
  STATE_URL="$url"
  STATE_CWD="$cwd"
  STATE_LOG_FILE="$(log_file_path "$cwd")"
  : > "$STATE_LOG_FILE"

  nohup happy acp opencode --attach "$url" --cwd "$cwd" --started-by hakim-happy-opencode > "$STATE_LOG_FILE" 2>&1 &
  STATE_PID=$!
  STATE_SESSION_ID=""
  save_state "$cwd"

  if STATE_SESSION_ID="$(wait_for_session_id "$STATE_PID" "$STATE_LOG_FILE" || true)"; then
    :
  fi

  if [ -n "$STATE_SESSION_ID" ]; then
    save_state "$cwd"
    printf 'Happy Session ID: %s\n' "$STATE_SESSION_ID"
  else
    printf 'Happy ACP started for %s\n' "$cwd"
  fi

  printf 'PID: %s\n' "$STATE_PID"
  printf 'Logs: %s\n' "$STATE_LOG_FILE"

  if ! process_running "$STATE_PID"; then
    printf 'ERROR: Happy ACP exited early. Check logs: %s\n' "$STATE_LOG_FILE" >&2
    exit 1
  fi
}

stop_session() {
  local cwd="$1"
  local stopped_via_daemon=false

  load_state "$cwd"
  if [ -z "$STATE_PID" ] && [ -z "$STATE_SESSION_ID" ]; then
    printf 'No Happy ACP session tracked for %s\n' "$cwd"
    return 0
  fi

  ensure_command happy

  if [ -n "$STATE_SESSION_ID" ]; then
    local daemon_output
    daemon_output="$(happy daemon stop-session "$STATE_SESSION_ID" 2>&1 || true)"
    if printf '%s\n' "$daemon_output" | grep -q '^Session stopped$'; then
      stopped_via_daemon=true
    fi
  fi

  if process_running "$STATE_PID"; then
    kill "$STATE_PID" 2> /dev/null || true
    sleep 1
    if process_running "$STATE_PID"; then
      kill -9 "$STATE_PID" 2> /dev/null || true
    fi
  fi

  clear_state "$cwd"
  if [ "$stopped_via_daemon" = true ]; then
    printf 'Stopped Happy ACP session %s for %s\n' "$STATE_SESSION_ID" "$cwd"
  else
    printf 'Stopped Happy ACP process for %s\n' "$cwd"
  fi
}

status_session() {
  local cwd="$1"

  load_state "$cwd"
  if [ -z "$STATE_PID" ] && [ -z "$STATE_SESSION_ID" ]; then
    printf 'Status: stopped\n'
    printf 'CWD: %s\n' "$cwd"
    return 0
  fi

  if [ -z "$STATE_SESSION_ID" ]; then
    STATE_SESSION_ID="$(extract_session_id "$STATE_LOG_FILE" || true)"
    if [ -n "$STATE_SESSION_ID" ]; then
      save_state "$cwd"
    fi
  fi

  if process_running "$STATE_PID"; then
    printf 'Status: running\n'
  else
    printf 'Status: stopped\n'
  fi
  printf 'CWD: %s\n' "$STATE_CWD"
  if [ -n "$STATE_SESSION_ID" ]; then
    printf 'Happy Session ID: %s\n' "$STATE_SESSION_ID"
  fi
  if [ -n "$STATE_PID" ]; then
    printf 'PID: %s\n' "$STATE_PID"
  fi
  if [ -n "$STATE_URL" ]; then
    printf 'Attach URL: %s\n' "$STATE_URL"
  fi
  printf 'Logs: %s\n' "$STATE_LOG_FILE"
}

print_logs() {
  local cwd="$1"

  load_state "$cwd"
  printf '%s\n' "$STATE_LOG_FILE"
}

COMMAND="start"
TARGET_DIR="$(pwd -P)"
PORT="$(default_port)"
URL=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    start|stop|restart|status|logs|list)
      COMMAND="$1"
      shift
      ;;
    --cwd)
      TARGET_DIR="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --url)
      URL="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [ "$COMMAND" = "list" ]; then
  list_sessions
  exit 0
fi

TARGET_DIR="$(resolve_cwd "$TARGET_DIR")"
if [ -z "$URL" ]; then
  URL="$(opencode_url_for_port "$PORT")"
fi

case "$COMMAND" in
  start)
    start_session "$TARGET_DIR" "$URL"
    ;;
  stop)
    stop_session "$TARGET_DIR"
    ;;
  restart)
    stop_session "$TARGET_DIR"
    start_session "$TARGET_DIR" "$URL"
    ;;
  status)
    status_session "$TARGET_DIR"
    ;;
  logs)
    print_logs "$TARGET_DIR"
    ;;
esac
