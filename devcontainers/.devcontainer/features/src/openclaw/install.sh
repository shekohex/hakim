#!/bin/bash
set -e

VERSION=${VERSION:-"2026.1.30"}

if ! command -v npm >/dev/null 2>&1; then
  if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
  fi
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to install openclaw" >&2
  exit 1
fi

if [ "${VERSION}" = "latest" ]; then
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
else
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g "openclaw@${VERSION}"
fi

if command -v openclaw >/dev/null 2>&1; then
  openclaw --version || openclaw -V || true
fi
