#!/bin/bash
# Build with caching enabled
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

# Create cache directories
CACHE_DIR="${REPO_ROOT}/.cache/distrobuilder"
APT_CACHE_DIR="${CACHE_DIR}/apt"
mkdir -p "${CACHE_DIR}" "${APT_CACHE_DIR}"

# Set up apt caching via environment
export APT_CACHE_DIR
export DEBOOTSTRAP_OPTS="--cache-dir=${APT_CACHE_DIR}"

OUT_DIR="${DISTROBUILDER_DIR}/out/${VARIANT}"
TMP_DIR="${REPO_ROOT}/.tmp/distrobuilder/${VARIANT}-${RELEASE}-${ARCH}"
ARTIFACT_NAME="hakim-${VARIANT}-${RELEASE}-${ARCH}.tar.xz"

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

export HAKIM_REPO_ROOT="${REPO_ROOT}"
export HAKIM_DISTROBUILDER_DIR="${DISTROBUILDER_DIR}"

echo "Building with cache: ${CACHE_DIR}"
echo "APT cache: ${APT_CACHE_DIR}"

(
  cd "${DISTROBUILDER_DIR}"
  # Use --cache-dir to enable distrobuilder caching
  distrobuilder build-lxc \
    --cache-dir "${CACHE_DIR}" \
    -o "image.variant=${VARIANT}" \
    -o "image.release=${RELEASE}" \
    -o "image.architecture=${ARCH}" \
    "hakim.yaml" \
    "${TMP_DIR}"
)

ROOTFS_TARBALL="${TMP_DIR}/rootfs.tar.xz"
META_TARBALL="${TMP_DIR}/meta.tar.xz"

if [ ! -f "${ROOTFS_TARBALL}" ]; then
  echo "ERROR: rootfs.tar.xz not found" >&2
  exit 1
fi

echo "Packaging..."
cd "${TMP_DIR}"
tar -cJf "${OUT_DIR}/${ARTIFACT_NAME}" rootfs.tar.xz meta.tar.xz

cd "${OUT_DIR}"
sha256sum "${ARTIFACT_NAME}" > sha256sums.txt

echo "Built: ${OUT_DIR}/${ARTIFACT_NAME}"
echo "Cache location: ${CACHE_DIR}"
echo "Cache size: $(du -sh ${CACHE_DIR} | cut -f1)"
