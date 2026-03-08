#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-hakim-coder}"

load_env_file() {
  local env_file="$1"

  if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
    return 0
  fi

  return 1
}

if [ -z "${CODER_VERSION:-}" ]; then
  load_env_file "$ROOT_DIR/.env" || load_env_file "$ROOT_DIR/docker/coder/.env" || true
fi

if [ -z "${CODER_VERSION:-}" ]; then
  printf 'CODER_VERSION must be set in the environment or a .env file\n' >&2
  exit 1
fi

CODER_VERSION="${CODER_VERSION#v}"
IMAGE_TAG="${IMAGE_NAME}:${CODER_VERSION}"

docker build \
  --build-arg "CODER_VERSION=${CODER_VERSION}" \
  --tag "$IMAGE_TAG" \
  --file "$ROOT_DIR/docker/coder/Dockerfile" \
  "$ROOT_DIR/docker/coder"

printf '%s\n' "$IMAGE_TAG"
