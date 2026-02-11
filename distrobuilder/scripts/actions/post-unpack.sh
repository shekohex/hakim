#!/bin/bash
set -euo pipefail

if [ -f /etc/apt/apt.conf.d/docker-clean ]; then
  rm -f /etc/apt/apt.conf.d/docker-clean
fi

if [ -f /etc/locale.gen ]; then
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
  locale-gen || true
fi

groupadd -f docker

if ! id coder >/dev/null 2>&1; then
  useradd -m -s /bin/bash coder --groups docker --user-group --uid 1000
fi

mkdir -p /etc/mise /usr/local/share/mise /etc/profile.d /home/coder /home/coder/project /home/coder/.config/mise
chown -R coder:coder /home/coder
