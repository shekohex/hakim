#!/bin/bash
set -e

VERSION=${VERSION:-"latest"}

if ! command -v npm >/dev/null 2>&1; then
  if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
  fi
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to install clawdbot" >&2
  exit 1
fi

if [ "${VERSION}" = "latest" ]; then
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g clawdbot@latest
else
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g "clawdbot@${VERSION}"
fi

if command -v clawdbot >/dev/null 2>&1; then
  clawdbot --version || clawdbot -V || true
fi
