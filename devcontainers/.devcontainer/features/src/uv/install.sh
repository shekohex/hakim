#!/bin/bash
set -e

PYTHON_VERSION=${PYTHON_VERSION:-${PYTHONVERSION:-"3.12.12"}}
UV_VERSION=${UV_VERSION:-${UVVERSION:-"0.9.28"}}

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

if [ -f /etc/profile.d/mise.sh ]; then
  source /etc/profile.d/mise.sh
fi

mise use --global "uv@${UV_VERSION}"

source /etc/profile.d/mise.sh

uv python install "${PYTHON_VERSION}"

uv python list

for bin_path in $(mise bin-paths); do
  for bin_file in "$bin_path"/*; do
    if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
      ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"
    fi
  done
done
