#!/bin/bash
# Contract smoke test for `cube-hakim-*` images.
#
# Verifies the Cube runtime contract that can be checked with plain Docker:
# envd readiness, toolchain resolution, Docker-in-sandbox, Xvfb + Chrome, and
# ordered SIGTERM teardown.
#
# This does NOT exercise the Cube control plane (templates, E2B SDK, TAP/shim
# cleanup). Use the Cube-level smoke script on the Cube Node for that.
#
# Usage:
#   scripts/smoke-test-cube-image.sh --image <ref> [--name <container>] [--keep]
#
# Requires a Docker daemon that permits --privileged containers.
set -euo pipefail

IMAGE=""
NAME="hakim-cube-smoke-$$"
KEEP=false
START_TIMEOUT="${CUBE_SMOKE_START_TIMEOUT:-180}"
STOP_TIMEOUT="${CUBE_SMOKE_STOP_TIMEOUT:-90}"
RUN_ARGS="${CUBE_SMOKE_RUN_ARGS:---privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:rw}"

function usage() {
  cat <<'EOF'
Usage: scripts/smoke-test-cube-image.sh --image <ref> [--name <container>] [--keep]

Options:
  --image <ref>     cube-hakim-* image to test (required)
  --name <name>     Container name (default: hakim-cube-smoke-<pid>)
  --keep            Leave the container around for inspection

Environment:
  CUBE_SMOKE_START_TIMEOUT   Seconds to wait for envd health (default 180)
  CUBE_SMOKE_STOP_TIMEOUT    Seconds for docker stop (default 90)
  CUBE_SMOKE_RUN_ARGS        Extra `docker run` flags
EOF
}

function require_option_value() {
  local option="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" = "-" ]]; then
    echo "$option requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --image)
    require_option_value "$1" "${2:-}"
    IMAGE="$2"
    shift 2
    continue
    ;;
  --name)
    require_option_value "$1" "${2:-}"
    NAME="$2"
    shift 2
    continue
    ;;
  --keep)
    KEEP=true
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "unknown argument: $1" >&2
    usage
    exit 2
    ;;
  esac
  shift
done

if [ -z "$IMAGE" ]; then
  echo "--image is required" >&2
  usage
  exit 2
fi

function log() {
  echo "[cube-smoke] $*"
}

function dump_logs() {
  echo "--- docker logs ($NAME) ---" >&2
  docker logs --tail 80 "$NAME" >&2 2>&1 || true
}

function fail() {
  echo "[cube-smoke][FAIL] $*" >&2
  dump_logs
  exit 1
}

function cleanup() {
  if [ "$KEEP" != "true" ]; then
    docker rm -f "$NAME" >/dev/null 2>&1 || true
  else
    log "keeping container $NAME"
  fi
}

function exec_root() {
  docker exec "$NAME" "$@"
}

function exec_coder() {
  docker exec -u coder -e HOME=/home/coder --workdir /home/coder "$NAME" "$@"
}

function assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" != "$expected" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

function wait_for_health() {
  local deadline=$((SECONDS + START_TIMEOUT)) code
  while [ "$SECONDS" -lt "$deadline" ]; do
    running="$(docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)"
    if [ "$running" != "true" ]; then
      fail "container exited before envd became ready"
    fi
    code="$(exec_root curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:49983/health 2>/dev/null || true)"
    if [ "$code" = "204" ]; then
      return 0
    fi
    sleep 1
  done
  fail "envd health did not return 204 within ${START_TIMEOUT}s (last code: ${code:-none})"
}

trap cleanup EXIT

log "starting $IMAGE as $NAME"
# shellcheck disable=SC2086
docker run -d --name "$NAME" $RUN_ARGS "$IMAGE" >/dev/null

log "waiting for envd /health"
wait_for_health
log "envd healthy (:49983/health -> 204)"

assert_eq "$(exec_root cat /proc/1/comm)" "tini" "PID 1"
assert_eq "$(exec_root printenv ENVD_PORT)" "49983" "ENVD_PORT"
assert_eq "$(exec_root printenv DISPLAY)" ":99" "DISPLAY"
assert_eq "$(exec_root printenv LIBGL_ALWAYS_SOFTWARE)" "1" "LIBGL_ALWAYS_SOFTWARE"
assert_eq "$(docker inspect --format '{{.State.Running}}' "$NAME")" "true" "container running"

log "checking baked runtime files"
exec_root test -x /usr/bin/envd
exec_root test -x /usr/local/bin/cube-entrypoint.sh
exec_root test -x /usr/local/bin/hakim-cube-entrypoint
exec_root test -s /etc/cubesandbox-envd-ref

log "checking Vulkan packages"
exec_root dpkg-query -W tini libvulkan1 mesa-vulkan-drivers >/dev/null
exec_root bash -c 'test -d /usr/share/vulkan/icd.d && ls /usr/share/vulkan/icd.d >/dev/null'

log "checking toolchains in a non-login coder shell"
exec_coder bash -c '
  set -eu
  for tool in node bun npm pnpm python uv mise docker docker-compose docker-buildx \
              git gh rg fd jq yq zip unzip rsync curl wget shellcheck google-chrome-stable chromedriver; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
  done
  node --version
  bun --version
  pnpm --version
  python --version
  uv --version
  mise --version
  docker --version
'

log "checking Docker daemon"
exec_root docker info >/dev/null
exec_coder docker info >/dev/null

log "running a nested container as coder"
exec_coder bash -c '
  set -eu
  dir="$(mktemp -d)"
  cp /usr/bin/envd "$dir/envd"
  printf "FROM scratch\nCOPY envd /envd\nENTRYPOINT [\"/envd\",\"-version\"]\n" > "$dir/Dockerfile"
  docker build -q -t hakim-cube-nested-smoke "$dir" >/dev/null
  out="$(docker run --rm hakim-cube-nested-smoke 2>&1)"
  [ -n "$out" ] || { echo "nested container produced no output" >&2; exit 1; }
  echo "nested-container-ok"
'

log "checking Xvfb on :99"
exec_coder bash -c 'DISPLAY=:99 xdpyinfo | head -n1' >/dev/null

log "executing JavaScript through Chrome"
exec_coder bash -c '
  set -eu
  [ "$DISPLAY" = ":99" ] || { echo "Chrome smoke requires DISPLAY=:99" >&2; exit 1; }
  page=/tmp/hakim-cube-chrome-smoke.html
  driver_log=/tmp/hakim-cube-chromedriver.log
  printf "%s\n" "<!doctype html><html><body><script>document.body.setAttribute(\"data-js\",\"chrome-js-ok\")</script></body></html>" > "$page"

  chromedriver --port=9515 --log-path="$driver_log" >/dev/null 2>&1 &
  driver_pid=$!
  cleanup_driver() {
    kill "$driver_pid" 2>/dev/null || true
    wait "$driver_pid" 2>/dev/null || true
  }
  trap cleanup_driver EXIT

  until curl -fsS http://127.0.0.1:9515/status >/dev/null 2>&1; do
    kill -0 "$driver_pid" 2>/dev/null || { cat "$driver_log" >&2 || true; exit 1; }
    sleep 0.1
  done

  session_response="$(curl -fsS -X POST http://127.0.0.1:9515/session \
    -H "Content-Type: application/json" \
    --data '{"capabilities":{"alwaysMatch":{"browserName":"chrome","goog:chromeOptions":{"args":["--no-sandbox","--disable-dev-shm-usage","--disable-gpu","--window-size=1280,1024"],"binary":"/usr/bin/google-chrome-stable"}}}}')"
  session_id="$(printf "%s" "$session_response" | jq -r '.value.sessionId // .sessionId // empty')"
  [ -n "$session_id" ] || { printf "%s\n" "$session_response" >&2; exit 1; }

  curl -fsS -X POST "http://127.0.0.1:9515/session/$session_id/url" \
    -H "Content-Type: application/json" \
    --data "{\"url\":\"file://$page\"}" >/dev/null
  result="$(curl -fsS -X POST "http://127.0.0.1:9515/session/$session_id/execute/sync" \
    -H "Content-Type: application/json" \
    --data '{"script":"return document.body.dataset.js","args":[]}')"
  marker="$(printf "%s" "$result" | jq -r '.value // empty')"
  [ "$marker" = "chrome-js-ok" ] || { printf "Chrome did not execute JavaScript: %s\n" "$result" >&2; exit 1; }
  curl -fsS -X DELETE "http://127.0.0.1:9515/session/$session_id" >/dev/null || true
  echo "chrome-js-ok"
'

log "stopping container (SIGTERM lifecycle)"
docker stop -t "$STOP_TIMEOUT" "$NAME" >/dev/null

assert_eq "$(docker inspect --format '{{.State.Running}}' "$NAME")" "false" "container stopped"

logs="$(docker logs "$NAME" 2>&1 || true)"
for marker in "stopping cube-entrypoint" "stopping dockerd" "stopping Xvfb"; do
  case "$logs" in
  *"$marker"*) ;;
  *) fail "teardown log missing marker: $marker" ;;
  esac
done

exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$NAME")"
if [ "$exit_code" != "0" ] && [ "$exit_code" != "143" ]; then
  fail "unexpected exit code after SIGTERM: $exit_code"
fi

log "smoke checks passed for $IMAGE (exit=$exit_code)"
