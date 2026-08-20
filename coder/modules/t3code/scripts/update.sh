#!/bin/bash
set -euo pipefail

export PATH="$HOME/.bun/bin:/usr/local/share/mise/shims:$HOME/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

if ! command -v bun > /dev/null 2>&1; then
  echo "ERROR: Bun is required to update T3 Code"
  exit 1
fi

if ! command -v sudo > /dev/null 2>&1; then
  echo "ERROR: sudo is required to restart the T3 Code systemd service"
  exit 1
fi

curl -fsSL https://github.com/shekohex/t3code/releases/download/fork-preview/install-github-package.sh | bash -s -- --bun

sudo systemctl restart t3code.service

sleep 1
if ! sudo systemctl is-active --quiet t3code.service; then
  sudo systemctl status --no-pager t3code.service || true
  echo "ERROR: T3 Code systemd service failed to restart"
  exit 1
fi

echo "T3 Code updated and t3code.service restarted successfully"
