#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTROBUILDER_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(cd "${DISTROBUILDER_DIR}/.." && pwd)

VARIANT=${1:-}
RELEASE=${2:-bookworm}
ARCH=${3:-amd64}

if [ -z "${VARIANT}" ]; then
  echo "Usage: $(basename "$0") <variant> [release] [arch]" >&2
  echo "Variants: base php dotnet js rust elixir" >&2
  exit 1
fi

case "${VARIANT}" in
base | php | dotnet | js | rust | elixir) ;;
*)
  echo "Unsupported variant: ${VARIANT}" >&2
  exit 1
  ;;
esac

OUT_DIR="${DISTROBUILDER_DIR}/out/${VARIANT}"
TMP_DIR="${REPO_ROOT}/.tmp/distrobuilder/${VARIANT}-${RELEASE}-${ARCH}"
ARTIFACT_NAME="hakim-${VARIANT}-${RELEASE}-${ARCH}.tar.xz"

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

export HAKIM_REPO_ROOT="${REPO_ROOT}"
export HAKIM_DISTROBUILDER_DIR="${DISTROBUILDER_DIR}"

(
  cd "${DISTROBUILDER_DIR}"
  distrobuilder build-lxc "hakim.yaml" -o "image.variant=${VARIANT}" -o "image.release=${RELEASE}" -o "image.architecture=${ARCH}" "${TMP_DIR}"
)

tarballs=("${TMP_DIR}"/*.tar.xz)
if [ ! -e "${tarballs[0]}" ]; then
  echo "No template tarball produced in ${TMP_DIR}" >&2
  exit 1
fi

cp "${tarballs[0]}" "${OUT_DIR}/${ARTIFACT_NAME}"

(
  cd "${OUT_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${ARTIFACT_NAME}" > sha256sums.txt
  else
    shasum -a 256 "${ARTIFACT_NAME}" > sha256sums.txt
  fi
)

echo "Built ${OUT_DIR}/${ARTIFACT_NAME}"
echo "Checksum: ${OUT_DIR}/sha256sums.txt"
