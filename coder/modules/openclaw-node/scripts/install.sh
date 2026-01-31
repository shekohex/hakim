#!/bin/bash
set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ARG_INSTALL_OPENCLAW=${ARG_INSTALL_OPENCLAW:-true}
ARG_OPENCLAW_VERSION=${ARG_OPENCLAW_VERSION:-latest}

if [ "${ARG_INSTALL_OPENCLAW}" != "true" ]; then
  exit 0
fi

if command_exists openclaw; then
  exit 0
fi

if [ "${ARG_OPENCLAW_VERSION}" = "latest" ]; then
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
else
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g "openclaw@${ARG_OPENCLAW_VERSION}"
fi

openclaw --version || openclaw -V || true
