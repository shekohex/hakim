#!/bin/bash
set -e

VERSION=${VERSION:-"latest"}

if [ "${VERSION}" = "latest" ]; then
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g clawdbot@latest
else
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g "clawdbot@${VERSION}"
fi

if command -v clawdbot >/dev/null 2>&1; then
  clawdbot --version || clawdbot -V || true
fi
