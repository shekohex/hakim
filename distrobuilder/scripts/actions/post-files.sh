#!/bin/bash
set -euo pipefail

RELEASE="${1:-}"

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
  printf '%s\n' "auto lo" "iface lo inet loopback" "" "source /etc/network/interfaces.d/*" > /etc/network/interfaces
fi

if ! grep -RqsE '^iface[[:space:]]+eth0[[:space:]]+inet[[:space:]]+' /etc/network/interfaces /etc/network/interfaces.d; then
  printf '%s\n' "auto eth0" "iface eth0 inet dhcp" > /etc/network/interfaces.d/eth0
fi

if [ "${RELEASE}" = "trixie" ]; then
  printf '%s\n' 'root:password' | chpasswd
  mkdir -p /etc/ssh/sshd_config.d
  printf '%s\n' 'PermitRootLogin yes' 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/00-hakim-bootstrap.conf
fi

rm -rf /var/lib/apt/lists/*
