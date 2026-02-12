#!/bin/bash
#
# Hakim LXC Template Builder
#
# Unified build script for creating LXC container templates with optional caching.
#
# Usage:
#   ./build.sh [OPTIONS] [VARIANT]
#
# Arguments:
#   VARIANT     Template variant to build (base, php, dotnet, js, rust, elixir)
#               If not specified and --all is used, builds all variants
#
# Options:
#   -a, --all           Build all variants (default if no variant specified)
#   -c, --cached        Enable APT and mise caching for faster rebuilds
#   -v, --variant NAME  Build specific variant (alternative to positional arg)
#   -r, --release NAME  Debian release (default: bookworm)
#   -A, --arch ARCH     Architecture (default: amd64)
#   -h, --help          Show this help message
#
# Examples:
#   # Build all variants without cache (CI mode)
#   ./build.sh --all
#
#   # Build all variants with caching (local development)
#   ./build.sh --all --cached
#
#   # Build specific variant with cache
#   ./build.sh --cached elixir
#   ./build.sh --variant elixir --cached
#
#   # Build base variant for arm64
#   ./build.sh --variant base --arch arm64
#
# Cache Locations:
#   APT cache:  .cache/distrobuilder/apt/
#   Mise cache: .cache/distrobuilder/mise/
#
# Environment Variables:
#   GITHUB_TOKEN    GitHub API token (for mise tool downloads)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTROBUILDER_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(cd "${DISTROBUILDER_DIR}/.." && pwd)

# Default values
VARIANT=""
RELEASE="bookworm"
ARCH="amd64"
CACHED=false
BUILD_ALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--all)
      BUILD_ALL=true
      shift
      ;;
    -c|--cached)
      CACHED=true
      shift
      ;;
    -v|--variant)
      VARIANT="$2"
      shift 2
      ;;
    -r|--release)
      RELEASE="$2"
      shift 2
      ;;
    -A|--arch)
      ARCH="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '/^#!/,/^$/p' "$0" | tail -n +2
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
    *)
      # Positional argument - variant name
      if [ -z "$VARIANT" ]; then
        VARIANT="$1"
      fi
      shift
      ;;
  esac
done

# If no variant specified and --all not set, default to building all
if [ -z "$VARIANT" ] && [ "$BUILD_ALL" = false ]; then
  BUILD_ALL=true
fi

# Validate variant if specified
if [ -n "$VARIANT" ]; then
  case "$VARIANT" in
    base|php|dotnet|js|rust|elixir)
      ;;
    *)
      echo "Error: Unknown variant '$VARIANT'" >&2
      echo "Supported variants: base, php, dotnet, js, rust, elixir" >&2
      exit 1
      ;;
  esac
fi

# Setup caching if enabled
setup_cache() {
  if [ "$CACHED" = true ]; then
    CACHE_DIR="${REPO_ROOT}/.cache/distrobuilder"
    APT_CACHE_DIR="${CACHE_DIR}/apt"
    MISE_CACHE_DIR="${CACHE_DIR}/mise"
    
    mkdir -p "${CACHE_DIR}" "${APT_CACHE_DIR}" "${MISE_CACHE_DIR}"
    
    export APT_CACHE_DIR
    export DEBOOTSTRAP_OPTS="--cache-dir=${APT_CACHE_DIR}"
    export MISE_CACHE_DIR
    export HAKIM_MISE_CACHE="${MISE_CACHE_DIR}"
    
    # Prepare mise cache directory for injection into build
    mkdir -p "${MISE_CACHE_DIR}/downloads"
    mkdir -p "${DISTROBUILDER_DIR}/cache/mise"
    rm -rf "${DISTROBUILDER_DIR}/cache/mise/downloads"
    ln -sf "${MISE_CACHE_DIR}/downloads" "${DISTROBUILDER_DIR}/cache/mise/downloads"
    
    echo "Cache enabled:"
    echo "  APT:  ${APT_CACHE_DIR} ($(du -sh ${APT_CACHE_DIR} 2>/dev/null | cut -f1 || echo 'empty'))"
    echo "  Mise: ${MISE_CACHE_DIR} ($(du -sh ${MISE_CACHE_DIR} 2>/dev/null | cut -f1 || echo 'empty'))"
  else
    # Still need to create empty cache directory for distrobuilder
    mkdir -p "${DISTROBUILDER_DIR}/cache/mise/downloads"
  fi
}

# Build a single variant
build_variant() {
  local variant="$1"
  local release="$2"
  local arch="$3"
  
  echo ""
  echo "=========================================="
  echo "Building variant: ${variant}"
  echo "Release: ${release}"
  echo "Architecture: ${arch}"
  echo "=========================================="
  
  local out_dir="${DISTROBUILDER_DIR}/out/${variant}"
  local tmp_dir="${REPO_ROOT}/.tmp/distrobuilder/${variant}-${release}-${arch}"
  local artifact_name="hakim-${variant}-${release}-${arch}.tar.xz"
  
  mkdir -p "${out_dir}" "${tmp_dir}"
  
  export HAKIM_REPO_ROOT="${REPO_ROOT}"
  export HAKIM_DISTROBUILDER_DIR="${DISTROBUILDER_DIR}"
  
  # Run distrobuilder
  (
    cd "${DISTROBUILDER_DIR}"
    if [ "$CACHED" = true ]; then
      distrobuilder build-lxc \
        --cache-dir "${CACHE_DIR}" \
        -o "image.variant=${variant}" \
        -o "image.release=${release}" \
        -o "image.architecture=${arch}" \
        "hakim.yaml" \
        "${tmp_dir}"
    else
      distrobuilder build-lxc \
        -o "image.variant=${variant}" \
        -o "image.release=${release}" \
        -o "image.architecture=${arch}" \
        "hakim.yaml" \
        "${tmp_dir}"
    fi
  )
  
  # Package the output
  local rootfs_tarball="${tmp_dir}/rootfs.tar.xz"
  local meta_tarball="${tmp_dir}/meta.tar.xz"
  
  if [ ! -f "${rootfs_tarball}" ]; then
    echo "ERROR: rootfs.tar.xz not found for ${variant}" >&2
    return 1
  fi
  
  echo "Packaging ${variant}..."
  cd "${tmp_dir}"
  tar -cJf "${out_dir}/${artifact_name}" rootfs.tar.xz meta.tar.xz
  
  cd "${out_dir}"
  sha256sum "${artifact_name}" > sha256sums.txt
  
  # Extract mise cache if caching is enabled
  if [ "$CACHED" = true ]; then
    echo "Extracting mise cache from ${variant} build..."
    mkdir -p "${MISE_CACHE_DIR}/downloads"
    if tar -tf "${tmp_dir}/rootfs.tar.xz" 2>/dev/null | grep -q "usr/local/share/mise/downloads"; then
      tar -xf "${tmp_dir}/rootfs.tar.xz" -C "${MISE_CACHE_DIR}/downloads" --strip-components=4 \
        usr/local/share/mise/downloads/ 2>/dev/null || true
    fi
  fi
  
  echo "Built: ${out_dir}/${artifact_name}"
  ls -lh "${out_dir}/${artifact_name}"
}

# Main build process
main() {
# Check for distrobuilder
if ! command -v distrobuilder &> /dev/null; then
  echo "ERROR: distrobuilder not found in PATH" >&2
  echo "" >&2
  echo "Install options:" >&2
  echo "  1. From source (recommended for Proxmox):" >&2
  echo "     sudo ./scripts/install-distrobuilder.sh" >&2
  echo "" >&2
  echo "  2. Via snap:" >&2
  echo "     sudo snap install distrobuilder --classic" >&2
  echo "" >&2
  exit 1
fi

echo "Hakim LXC Template Builder"
echo "=========================="
echo "distrobuilder: $(distrobuilder --version 2>/dev/null || echo 'unknown')"
  
  # Setup cache
  setup_cache
  
  # Track failures
  local failures=()
  
  # Build variants
  if [ "$BUILD_ALL" = true ]; then
    echo "Building all variants..."
    for variant in base php dotnet js rust elixir; do
      if ! build_variant "$variant" "$RELEASE" "$ARCH"; then
        failures+=("$variant")
        echo "WARNING: Build failed for ${variant}" >&2
      fi
    done
  else
    if ! build_variant "$VARIANT" "$RELEASE" "$ARCH"; then
      failures+=("$VARIANT")
    fi
  fi
  
  # Summary
  echo ""
  echo "=========================================="
  echo "Build Complete"
  echo "=========================================="
  
  if [ ${#failures[@]} -eq 0 ]; then
    echo "All builds successful!"
    
    if [ "$CACHED" = true ]; then
      echo ""
      echo "Cache Statistics:"
      echo "  APT:  $(du -sh ${APT_CACHE_DIR} 2>/dev/null | cut -f1 || echo '0')"
      echo "  Mise: $(du -sh ${MISE_CACHE_DIR} 2>/dev/null | cut -f1 || echo '0')"
      echo "  Mise files: $(find ${MISE_CACHE_DIR}/downloads -type f 2>/dev/null | wc -l)"
    fi
    
    echo ""
    echo "Output directory: ${DISTROBUILDER_DIR}/out/"
    ls -lh ${DISTROBUILDER_DIR}/out/*/
    
    exit 0
  else
    echo "ERROR: The following builds failed:"
    printf '  - %s\n' "${failures[@]}"
    exit 1
  fi
}

main
