#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/shekohex}"
PULLED=0
FAILED=0

function log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')][$level] $*"
}

function info() { log "INFO" "$@"; }
function warn() { log "WARN" "$@"; }
function error() { log "ERROR" "$@"; }
function success() { log "OK" "$*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --registry <registry>        Source image registry/namespace (default: ghcr.io/shekohex)
  --local-registry <host:port/namespace>
                               Shortcut for --registry (example: 192.168.1.105:5000/hakim)
  -h, --help                   Show this help
EOF
  exit 0
}

function on_exit() {
  echo
  info "Pull summary: $PULLED succeeded, $FAILED failed"
  if [ $FAILED -eq 0 ]; then
    success "All images pulled successfully"
  fi
}
trap on_exit EXIT

function login_ghcr() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    return 0
  fi

  if command -v gh &>/dev/null; then
    info "Attempting to login to GHCR via gh CLI..."
    if TOKEN=$(gh auth token 2>/dev/null); then
      export GITHUB_TOKEN="$TOKEN"
      echo "$TOKEN" | docker login ghcr.io -u "$TOKEN" --password-stdin 2>/dev/null &&
        success "Logged in to GHCR" && return 0
    fi
  fi

  warn "Not logged in to GHCR. Pulling public images only..."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --registry)
    [[ "$#" -gt 1 ]] || { error "missing value for $1"; exit 1; }
    REGISTRY="$2"
    shift 2
    ;;
  --local-registry)
    [[ "$#" -gt 1 ]] || { error "missing value for $1"; exit 1; }
    REGISTRY="$2"
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  *)
    error "Unknown parameter passed: $1"
    usage
    ;;
  esac
done

function pull_image() {
  local image="$1"
  local display_name="${2:-$image}"

  info "Pulling $display_name..."
  if docker pull "$image" 2>/dev/null; then
    success "$display_name"
    ((PULLED++)) || true
  else
    error "Failed to pull $display_name"
    ((FAILED++)) || true
  fi
}

function dangling_images() {
  docker images -f dangling=true -q 2>/dev/null || true
}

if [[ "${REGISTRY}" == ghcr.io/* ]]; then
  login_ghcr
else
  info "Using registry $REGISTRY (skipping GHCR auth)"
fi

info "Pulling base images..."
pull_image "$REGISTRY/hakim-base:latest" "base:latest"

info "Pulling variant images..."
for variant_dir in devcontainers/.devcontainer/images/*; do
  variant=$(basename "$variant_dir")
  pull_image "$REGISTRY/hakim-$variant:latest" "$variant:latest"
done

dangling=$(dangling_images)
if [ -n "$dangling" ]; then
  count=$(printf "%s\n" "$dangling" | wc -l | tr -d ' ')
  warn "Found $count dangling images"
  info "Cleanup: docker image prune -f"
fi
