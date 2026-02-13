#!/bin/bash
set -euo pipefail

groupadd -f docker

if ! id coder >/dev/null 2>&1; then
  useradd -m -s /bin/bash coder --groups docker --user-group --uid 1000
fi

printf '%s\n' "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder
chmod 0440 /etc/sudoers.d/coder

mkdir -p /home/coder/.config/mise /home/coder/project
chown -R coder:coder /home/coder

if [ -f /usr/local/share/hakim/assets/starship.toml ]; then
  cp /usr/local/share/hakim/assets/starship.toml /etc/starship.toml
fi

if command -v mise >/dev/null 2>&1; then
  for bin_path in $(mise bin-paths); do
    if [ -d "${bin_path}"; then
      for bin_file in "${bin_path}"/*; do
        if [ -f "${bin_file}" ] && [ -x "${bin_file}" ]; then
          bin_name=$(basename "${bin_file}")
          ln -sf "${bin_file}" "/usr/local/bin/${bin_name}"
          if [ ! -e "/usr/bin/${bin_name}" ]; then
            ln -sf "/usr/local/bin/${bin_name}" "/usr/bin/${bin_name}"
          fi
        fi
      done
    fi
  done
fi

for tool in mise coder code-server docker docker-compose; do
  if [ -x "/usr/local/bin/${tool}" ] && [ ! -e "/usr/bin/${tool}" ]; then
    ln -sf "/usr/local/bin/${tool}" "/usr/bin/${tool}"
  fi
done

mkdir -p /etc/network/interfaces.d

if [ ! -f /etc/network/interfaces ]; then
  printf '%s\n' "auto lo" "iface lo inet loopback" > /etc/network/interfaces
fi

rm -rf /var/lib/apt/lists/*
