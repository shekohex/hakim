#!/bin/bash
set -euo pipefail

KEEP_HOURS="${KEEP_HOURS:-168}"
PRUNE_ALL_IMAGES=false

function log() {
  local level="$1"
  shift
  echo "[$(date +"%Y-%m-%d %H:%M:%S")][$level] $*"
}

function info() {
  log "INFO" "$@"
}

function usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --all-images        Prune all unused images (ignores KEEP_HOURS)
  --keep-hours <n>    Prune unused images older than n hours (default: 168)
  --help, -h          Show this help

Environment:
  KEEP_HOURS          Same as --keep-hours
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --all-images)
    PRUNE_ALL_IMAGES=true
    ;;
  --keep-hours)
    KEEP_HOURS="$2"
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

if ! [[ "$KEEP_HOURS" =~ ^[0-9]+$ ]]; then
  echo "KEEP_HOURS must be a positive integer"
  exit 1
fi

function list_old_builders() {
  docker buildx ls 2>/dev/null | awk 'NR>1 && $1 !~ /^\\_/ && $1 != "" {name=$1; gsub(/\*/, "", name); if (name ~ /^hakim-builder(-http)?-[0-9]+$/) print name}' | sort -u
}

function remove_old_builders() {
  local old_builders
  old_builders="$(list_old_builders || true)"

  if [ -z "$old_builders" ]; then
    info "No old timestamped buildx builders found"
    return
  fi

  info "Removing old timestamped buildx builders"
  printf '%s\n' "$old_builders"
  printf '%s\n' "$old_builders" | xargs -r docker buildx rm
}

function prune_builder_cache() {
  local builder="$1"
  if docker buildx inspect "$builder" >/dev/null 2>&1; then
    info "Pruning buildx cache for builder '$builder'"
    docker buildx prune --builder "$builder" --all --force
  fi
}

function prune_images() {
  if [ "$PRUNE_ALL_IMAGES" = true ]; then
    info "Pruning all unused images"
    docker image prune -a -f
  else
    info "Pruning unused images older than ${KEEP_HOURS}h"
    docker image prune -a -f --filter "until=${KEEP_HOURS}h"
  fi
}

info "Docker usage before cleanup"
docker system df

remove_old_builders
prune_builder_cache "hakim-builder-http"
prune_builder_cache "hakim-builder"

info "Pruning classic builder cache"
docker builder prune -a -f

prune_images

info "Docker usage after cleanup"
docker system df

info "Cleanup completed"
