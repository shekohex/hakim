#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER_DIR="$ROOT_DIR/providers/hakim"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/.terraform/providers-mirror}"
PROVIDER_VERSION="${PROVIDER_VERSION:-0.1.0}"
TARGET_OS="${TARGET_OS:-linux}"
TARGET_ARCH="${TARGET_ARCH:-amd64}"
INSTALL_DIR="$OUTPUT_ROOT/registry.terraform.io/shekohex/hakim/${PROVIDER_VERSION}/${TARGET_OS}_${TARGET_ARCH}"
OUTPUT_PATH="$INSTALL_DIR/terraform-provider-hakim_v${PROVIDER_VERSION}"

mkdir -p "$INSTALL_DIR"

(
  cd "$PROVIDER_DIR"
  go build \
    -trimpath \
    -buildvcs=false \
    -ldflags "-s -w -X main.version=${PROVIDER_VERSION}" \
    -o "$OUTPUT_PATH" \
    .
)

printf '%s\n' "$OUTPUT_PATH"
