#!/bin/bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-$(hostname -s)}"
DATASTORE_ID="${DATASTORE_ID:-local}"

variants=(base php dotnet js rust elixir)

for variant in "${variants[@]}"; do
  reference="ghcr.io/shekohex/hakim-${variant}:latest"
  if [[ "${variant}" == "base" ]]; then
    reference="ghcr.io/shekohex/hakim-base:latest"
  fi

  pvesh create "/nodes/${NODE_NAME}/storage/${DATASTORE_ID}/oci-registry-pull" \
    --reference "${reference}" \
    --filename "hakim-${variant}_latest.tar"
done
