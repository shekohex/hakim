#!/bin/bash
# Hakim CubeSandbox runtime supervisor.
#
# Runs as the single child of tini (PID 1) inside a Cube microVM. It starts
# only the services a Cube sandbox needs (Docker daemon + Xvfb) and then
# delegates the envd/application lifecycle to the upstream CubeSandbox
# entrypoint as a supervised child.
#
# Ordering: the upstream entrypoint starts envd only after this script has
# confirmed Docker and Xvfb are ready. A 2xx on envd `:49983/health` (the Cube
# template readiness probe) therefore also implies the display and Docker are
# usable, which is what the template snapshot captures.
#
# Shutdown: SIGTERM/SIGINT are forwarded to the entrypoint process group
# (envd, application, Chrome, ...), then Docker is asked to stop (dockerd stops
# its child containers), then Xvfb. Every service runs in its own session so a
# stuck child cannot keep the sandbox alive. Children are reaped before exit.

set -uo pipefail

log() { printf '[hakim-cube] %s\n' "$*" >&2; }

CUBE_ENTRYPOINT="${CUBE_ENTRYPOINT:-/usr/local/bin/cube-entrypoint.sh}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
DOCKER_EXEC_ROOT="${DOCKER_EXEC_ROOT:-/var/run/docker}"
DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"
DOCKER_PID_FILE="${DOCKER_PID_FILE:-/var/run/docker.pid}"
DOCKER_LOG_FILE="${DOCKER_LOG_FILE:-/var/log/dockerd.log}"
DOCKERD_EXTRA_ARGS="${DOCKERD_EXTRA_ARGS:-}"
DOCKER_STORAGE_DRIVERS="${DOCKER_STORAGE_DRIVERS:-overlay2 fuse-overlayfs vfs}"
DOCKER_IPTABLES_FALLBACK="${DOCKER_IPTABLES_FALLBACK:-true}"
DOCKER_START_TIMEOUT="${DOCKER_START_TIMEOUT:-30}"
DOCKER_STOP_TIMEOUT="${DOCKER_STOP_TIMEOUT:-30}"
XVFB_LOG_FILE="${XVFB_LOG_FILE:-/var/log/xvfb.log}"
XVFB_SCREEN="${XVFB_SCREEN:-1280x1024x24}"
XVFB_READY_TIMEOUT="${XVFB_READY_TIMEOUT:-20}"
SERVICE_STOP_TIMEOUT="${SERVICE_STOP_TIMEOUT:-20}"
STRICT_RUNTIME="${HAKIM_CUBE_STRICT_RUNTIME:-true}"

export DISPLAY="${DISPLAY:-:99}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

RUN_DIR=""
LAST_LAUNCH_PID=""
AWAITED_PGID=""
DOCKER_PGID=""
XVFB_PGID=""
ENTRYPOINT_PGID=""
SHUTTING_DOWN=false

group_alive() {
  [ -n "${1:-}" ] && kill -0 "-$1" 2>/dev/null
}

stop_group() {
  local pgid="${1:-}" label="$2" timeout="$3" i=0
  [ -n "$pgid" ] || return 0
  group_alive "$pgid" || return 0

  log "stopping $label (pgid=$pgid)"
  kill -TERM "-$pgid" 2>/dev/null || true

  while [ "$i" -lt $((timeout * 10)) ]; do
    if ! group_alive "$pgid"; then
      log "$label stopped"
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  log "$label did not stop within ${timeout}s; sending SIGKILL"
  kill -KILL "-$pgid" 2>/dev/null || true
  sleep 1
  group_alive "$pgid" && log "WARN: $label still present after SIGKILL" || log "$label killed"
  return 0
}

launch_detached() {
  # launch_detached <pidfile> <logfile|-> <command...>
  # Starts the command as a session leader. The session id is written to
  # <pidfile>, which is also the process group id used to signal the tree.
  local pidfile="$1" logfile="$2"
  shift 2
  rm -f "$pidfile"
  if [ "$logfile" = "-" ]; then
    setsid bash -c 'echo $$ > "$0"; exec "$@"' "$pidfile" "$@" &
  else
    setsid bash -c 'echo $$ > "$0"; exec "$@"' "$pidfile" "$@" >>"$logfile" 2>&1 &
  fi
  LAST_LAUNCH_PID="$!"
}

stop_failed_launch() {
  local pidfile="$1" label="$2" pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    stop_group "$pid" "$label" 5
  elif [ -n "$LAST_LAUNCH_PID" ]; then
    kill -TERM "$LAST_LAUNCH_PID" 2>/dev/null || true
    wait "$LAST_LAUNCH_PID" 2>/dev/null || true
  fi
  LAST_LAUNCH_PID=""
}

await_pgid() {
  local pidfile="$1" label="$2" waited=0
  AWAITED_PGID=""
  while [ ! -s "$pidfile" ]; do
    [ "$SHUTTING_DOWN" = "true" ] && return 130
    waited=$((waited + 1))
    if [ "$waited" -ge 100 ]; then
      log "timed out waiting for $label to start"
      return 1
    fi
    sleep 0.05
  done
  AWAITED_PGID="$(cat "$pidfile")"
}

remove_stale_pidfile() {
  local pidfile="$1" label="$2" pid
  [ -f "$pidfile" ] || return 0
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pidfile"
    log "removed stale $label pid file $pidfile"
  else
    log "WARN: $label pid file $pidfile points at live pid $pid"
  fi
}

cleanup_stale_runtime_state() {
  local docker_pid containerd_pid
  mkdir -p "$DOCKER_EXEC_ROOT" "$DOCKER_DATA_ROOT" "$(dirname "$DOCKER_LOG_FILE")"

  docker_pid="$(cat "$DOCKER_PID_FILE" 2>/dev/null || true)"
  if [ -S "$DOCKER_SOCKET" ] && { [ -z "$docker_pid" ] || ! kill -0 "$docker_pid" 2>/dev/null; }; then
    rm -f "$DOCKER_SOCKET"
    log "removed stale docker socket $DOCKER_SOCKET"
  fi

  remove_stale_pidfile "$DOCKER_PID_FILE" dockerd
  remove_stale_pidfile "$DOCKER_EXEC_ROOT/containerd/containerd.pid" containerd

  local containerd_dir="$DOCKER_EXEC_ROOT/containerd"
  containerd_pid="$(cat "$DOCKER_EXEC_ROOT/containerd/containerd.pid" 2>/dev/null || true)"
  if [ -d "$containerd_dir" ] && { [ -z "$containerd_pid" ] || ! kill -0 "$containerd_pid" 2>/dev/null; }; then
    rm -f \
      "$containerd_dir/containerd.sock" \
      "$containerd_dir/containerd.sock.ttrpc" \
      "$containerd_dir/containerd-debug.sock"
  fi
}

docker_ready() {
  docker info >/dev/null 2>&1
}

wait_for_docker() {
  local timeout="$1" i=0
  while [ "$i" -lt $((timeout * 10)) ]; do
    [ "$SHUTTING_DOWN" = "true" ] && return 130
    if docker_ready; then
      return 0
    fi
    group_alive "$DOCKER_PGID" || return 1
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

start_docker() {
  local attempt driver extra
  local -a attempts=()

  [ "$SHUTTING_DOWN" = "true" ] && return 130

  for driver in $DOCKER_STORAGE_DRIVERS; do
    attempts+=("$driver::${DOCKERD_EXTRA_ARGS}")
  done
  if [ "$DOCKER_IPTABLES_FALLBACK" = "true" ]; then
    # netfilter may be unavailable in the microVM guest kernel; retry every
    # driver with Docker networking disabled before giving up.
    for driver in $DOCKER_STORAGE_DRIVERS; do
      attempts+=("$driver::${DOCKERD_EXTRA_ARGS} --iptables=false --ip6tables=false")
    done
  fi

  for attempt in "${attempts[@]}"; do
    [ "$SHUTTING_DOWN" = "true" ] && return 130
    driver="${attempt%%::*}"
    extra="${attempt#*::}"

    cleanup_stale_runtime_state
    [ "$SHUTTING_DOWN" = "true" ] && return 130
    : >"$DOCKER_LOG_FILE"

    # shellcheck disable=SC2086
    launch_detached "$RUN_DIR/dockerd.pid" "$DOCKER_LOG_FILE" dockerd \
      --host="unix://${DOCKER_SOCKET}" \
      --data-root="$DOCKER_DATA_ROOT" \
      --exec-root="$DOCKER_EXEC_ROOT" \
      --pidfile="$DOCKER_PID_FILE" \
      --storage-driver="$driver" $extra

    if await_pgid "$RUN_DIR/dockerd.pid" "dockerd ($driver)"; then
      DOCKER_PGID="$AWAITED_PGID"
    else
      stop_failed_launch "$RUN_DIR/dockerd.pid" "dockerd ($driver)"
      DOCKER_PGID=""
      continue
    fi

    if wait_for_docker "$DOCKER_START_TIMEOUT"; then
      log "docker ready (storage-driver=$driver)"
      return 0
    fi

    if [ "$SHUTTING_DOWN" = "true" ]; then
      stop_group "$DOCKER_PGID" "dockerd ($driver)" 10
      DOCKER_PGID=""
      return 130
    fi

    log "dockerd not ready with storage-driver=$driver; last log lines:"
    tail -n 20 "$DOCKER_LOG_FILE" >&2 || true
    stop_group "$DOCKER_PGID" "dockerd ($driver)" 10
    DOCKER_PGID=""
  done

  return 1
}

start_xvfb() {
  [ "$SHUTTING_DOWN" = "true" ] && return 130
  if [ "$DISPLAY" != ":99" ]; then
    log "DISPLAY=$DISPLAY is not :99; skipping Xvfb"
    return 0
  fi

  : >"$XVFB_LOG_FILE"
  launch_detached "$RUN_DIR/xvfb.pid" "$XVFB_LOG_FILE" \
    Xvfb "$DISPLAY" -screen 0 "$XVFB_SCREEN" -nolisten tcp
  if await_pgid "$RUN_DIR/xvfb.pid" Xvfb; then
    XVFB_PGID="$AWAITED_PGID"
  else
    stop_failed_launch "$RUN_DIR/xvfb.pid" Xvfb
    XVFB_PGID=""
    [ "$SHUTTING_DOWN" = "true" ] && return 130
    return 1
  fi

  local i=0
  while [ "$i" -lt $((XVFB_READY_TIMEOUT * 10)) ]; do
    [ "$SHUTTING_DOWN" = "true" ] && return 130
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
      [ "$SHUTTING_DOWN" = "true" ] && return 130
      log "Xvfb ready on $DISPLAY ($XVFB_SCREEN)"
      return 0
    fi
    group_alive "$XVFB_PGID" || {
      log "Xvfb exited before becoming ready"
      tail -n 20 "$XVFB_LOG_FILE" >&2 || true
      return 1
    }
    sleep 0.1
    i=$((i + 1))
  done

  log "Xvfb did not become ready on $DISPLAY within ${XVFB_READY_TIMEOUT}s"
  tail -n 20 "$XVFB_LOG_FILE" >&2 || true
  return 1
}

handle_required_failure() {
  local service="$1"
  if [ "$STRICT_RUNTIME" = "true" ]; then
    log "ERROR: $service failed to start"
    shutdown_all
    exit 1
  fi
  log "WARN: $service failed to start; continuing because HAKIM_CUBE_STRICT_RUNTIME=false"
}

on_signal() {
  local sig="$1"
  if [ "$SHUTTING_DOWN" = "true" ]; then
    return 0
  fi
  SHUTTING_DOWN=true
  log "received SIG$sig; forwarding to sandbox processes"
  if [ -n "$ENTRYPOINT_PGID" ]; then
    kill -"$sig" "-$ENTRYPOINT_PGID" 2>/dev/null || true
  fi
}

stop_and_reap() {
  # stop_group only guarantees the kill; waiting on the session leader reaps
  # the zombie. The service leaders are direct children of this script.
  stop_group "$1" "$2" "$3"
  wait "$1" 2>/dev/null || true
}

shutdown_all() {
  if [ "$SHUTTING_DOWN" != "true" ]; then
    log "shutting down sandbox runtime"
  fi
  SHUTTING_DOWN=true

  if [ -n "$ENTRYPOINT_PGID" ]; then
    stop_and_reap "$ENTRYPOINT_PGID" "cube-entrypoint (envd + applications)" "$SERVICE_STOP_TIMEOUT"
    ENTRYPOINT_PGID=""
  fi

  if [ -n "$DOCKER_PGID" ]; then
    stop_and_reap "$DOCKER_PGID" "dockerd" "$DOCKER_STOP_TIMEOUT"
    DOCKER_PGID=""
  fi

  if [ -n "$XVFB_PGID" ]; then
    stop_and_reap "$XVFB_PGID" "Xvfb" "$SERVICE_STOP_TIMEOUT"
    XVFB_PGID=""
  fi

  [ -n "$RUN_DIR" ] && rm -rf "$RUN_DIR"
}

main() {
  RUN_DIR="$(mktemp -d /tmp/hakim-cube.XXXXXX)" || {
    log "ERROR: cannot create runtime directory"
    exit 1
  }

  trap 'on_signal TERM' TERM
  trap 'on_signal INT' INT
  trap 'on_signal HUP' HUP

  log "starting Cube runtime (envd port ${ENVD_PORT:-49983}, display $DISPLAY)"

  if ! start_docker; then
    if [ "$SHUTTING_DOWN" = "true" ]; then
      shutdown_all
      exit 0
    fi
    handle_required_failure "Docker daemon"
  fi

  if [ "$SHUTTING_DOWN" = "true" ]; then
    shutdown_all
    exit 0
  fi

  if ! start_xvfb; then
    if [ "$SHUTTING_DOWN" = "true" ]; then
      shutdown_all
      exit 0
    fi
    handle_required_failure "Xvfb"
  fi

  if [ "$SHUTTING_DOWN" = "true" ]; then
    log "shutdown requested during startup"
    shutdown_all
    exit 0
  fi

  launch_detached "$RUN_DIR/entrypoint.pid" - "$CUBE_ENTRYPOINT" "$@"
  if await_pgid "$RUN_DIR/entrypoint.pid" cube-entrypoint; then
    ENTRYPOINT_PGID="$AWAITED_PGID"
  else
    stop_failed_launch "$RUN_DIR/entrypoint.pid" cube-entrypoint
    log "ERROR: could not start $CUBE_ENTRYPOINT"
    shutdown_all
    exit 1
  fi
  log "delegating envd/application lifecycle to $CUBE_ENTRYPOINT (pgid=$ENTRYPOINT_PGID)"

  local exit_code=0
  while true; do
    if group_alive "$ENTRYPOINT_PGID"; then
      wait "$ENTRYPOINT_PGID" 2>/dev/null
      exit_code=$?
      if [ "$exit_code" -gt 128 ] && group_alive "$ENTRYPOINT_PGID"; then
        continue
      fi
    fi
    break
  done

  log "sandbox foreground process exited (status=$exit_code)"
  shutdown_all
  exit "$exit_code"
}

main "$@"
