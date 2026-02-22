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

rm -rf /root/.cache/uv /root/.cache/mise /usr/local/share/mise/cache /usr/local/share/mise/downloads
