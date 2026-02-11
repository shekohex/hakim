#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

RELEASE=${1:-bookworm}
ARCH=${2:-amd64}

for variant in base php dotnet js rust elixir; do
  "${SCRIPT_DIR}/build-variant.sh" "${variant}" "${RELEASE}" "${ARCH}"
done
