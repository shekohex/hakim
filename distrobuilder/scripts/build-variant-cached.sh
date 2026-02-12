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
MISE_CACHE_DIR="${CACHE_DIR}/mise"
mkdir -p "${CACHE_DIR}" "${APT_CACHE_DIR}" "${MISE_CACHE_DIR}"

# Set up apt caching via environment
export APT_CACHE_DIR
export DEBOOTSTRAP_OPTS="--cache-dir=${APT_CACHE_DIR}"

# Set up mise caching - we'll mount this into the build
export MISE_CACHE_DIR
export HAKIM_MISE_CACHE="${MISE_CACHE_DIR}"

OUT_DIR="${DISTROBUILDER_DIR}/out/${VARIANT}"
TMP_DIR="${REPO_ROOT}/.tmp/distrobuilder/${VARIANT}-${RELEASE}-${ARCH}"
ARTIFACT_NAME="hakim-${VARIANT}-${RELEASE}-${ARCH}.tar.xz"

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

export HAKIM_REPO_ROOT="${REPO_ROOT}"
export HAKIM_DISTROBUILDER_DIR="${DISTROBUILDER_DIR}"

echo "Building with cache: ${CACHE_DIR}"
echo "APT cache: ${APT_CACHE_DIR}"
echo "MISE cache: ${MISE_CACHE_DIR}"

# Note: Mise cache is extracted after build, not injected during build
# This avoids breaking CI builds while still enabling local caching

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

# Extract updated mise cache from built image for future builds
echo ""
echo "Extracting mise cache from build..."
mkdir -p "${MISE_CACHE_DIR}/downloads"
if tar -tf "${TMP_DIR}/rootfs.tar.xz" | grep -q "usr/local/share/mise/downloads"; then
  tar -xf "${TMP_DIR}/rootfs.tar.xz" -C "${MISE_CACHE_DIR}/downloads" --strip-components=4 \
    usr/local/share/mise/downloads/ 2>/dev/null || true
  echo "Updated mise cache with $(find ${MISE_CACHE_DIR}/downloads -type f 2>/dev/null | wc -l) files"
fi

echo ""
echo "Built: ${OUT_DIR}/${ARTIFACT_NAME}"
echo ""
echo "=== Cache Statistics ==="
echo "APT cache: $(du -sh ${APT_CACHE_DIR} 2>/dev/null | cut -f1 || echo '0')"
echo "MISE cache: $(du -sh ${MISE_CACHE_DIR} 2>/dev/null | cut -f1 || echo '0')"
echo "Total: $(du -sh ${CACHE_DIR} | cut -f1)"
