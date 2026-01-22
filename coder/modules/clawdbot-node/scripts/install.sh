#!/bin/bash
set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ARG_INSTALL_CLAWDBOT=${ARG_INSTALL_CLAWDBOT:-true}
ARG_CLAWDBOT_VERSION=${ARG_CLAWDBOT_VERSION:-latest}

if [ "${ARG_INSTALL_CLAWDBOT}" != "true" ]; then
  exit 0
fi

if command_exists clawdbot; then
  exit 0
fi

if [ "${ARG_CLAWDBOT_VERSION}" = "latest" ]; then
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g clawdbot@latest
else
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g "clawdbot@${ARG_CLAWDBOT_VERSION}"
fi

clawdbot --version || clawdbot -V || true
