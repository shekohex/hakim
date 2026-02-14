#!/bin/bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-$(hostname -s)}"
DATASTORE_ID="${DATASTORE_ID:-local}"
TEMPLATE_TAG="${TEMPLATE_TAG:-latest}"
FORCE_REPLACE="${FORCE_REPLACE:-0}"
VARIANTS="${VARIANTS:-base,php,dotnet,js,rust,elixir}"

IFS=',' read -r -a variants <<< "${VARIANTS}"

for raw_variant in "${variants[@]}"; do
  variant="${raw_variant//[[:space:]]/}"
  if [[ -z "${variant}" ]]; then
    continue
  fi

  reference="ghcr.io/shekohex/hakim-${variant}:${TEMPLATE_TAG}"
  if [[ "${variant}" == "base" ]]; then
    reference="ghcr.io/shekohex/hakim-base:${TEMPLATE_TAG}"
  fi

  file_name="hakim-${variant}_${TEMPLATE_TAG}.tar"
  volume_id="${DATASTORE_ID}:vztmpl/${file_name}"

  if pvesm list "${DATASTORE_ID}" --content vztmpl | awk '{print $1}' | grep -Fxq "${volume_id}"; then
    if [[ "${FORCE_REPLACE}" == "1" ]]; then
      pvesm free "${volume_id}"
    else
      continue
    fi
  fi

  pvesh create "/nodes/${NODE_NAME}/storage/${DATASTORE_ID}/oci-registry-pull" \
    --reference "${reference}" \
    --filename "${file_name}"
done
