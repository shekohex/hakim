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
#   -c, --cached        Enable source and mise caching for faster rebuilds
#   -v, --variant NAME  Build specific variant (alternative to positional arg)
#   -r, --release NAME  Debian release (default: bookworm)
#   -A, --arch ARCH     Architecture (default: amd64)
#   -p, --apt-proxy URL Use apt-cacher-ng proxy (e.g., http://localhost:3142)
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
#   # Build using apt-cacher-ng proxy
#   ./build.sh --all --apt-proxy http://localhost:3142
#
# Cache Locations:
#   Sources:  .cache/distrobuilder/sources/
#   Mise:     .cache/distrobuilder/mise/
#
# Environment Variables:
#   GITHUB_TOKEN    GitHub API token (for mise tool downloads)

set -euo pipefail

# Find repo root using git (works regardless of where script is run from)
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "ERROR: Not in a git repository. Please run from within the hakim repo." >&2
  exit 1
fi

SCRIPT_DIR="${REPO_ROOT}/distrobuilder/scripts"
DISTROBUILDER_DIR="${REPO_ROOT}/distrobuilder"

# Verify directories exist
if [ ! -d "${DISTROBUILDER_DIR}" ]; then
  echo "ERROR: distrobuilder directory not found at ${DISTROBUILDER_DIR}" >&2
  exit 1
fi

if [ ! -f "${DISTROBUILDER_DIR}/hakim.yaml" ]; then
  echo "ERROR: hakim.yaml not found at ${DISTROBUILDER_DIR}/hakim.yaml" >&2
  exit 1
fi

# Default values
VARIANT=""
RELEASE="bookworm"
ARCH="amd64"
CACHED=false
BUILD_ALL=false
APT_PROXY=""

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
    -p|--apt-proxy)
      APT_PROXY="$2"
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

# Validate and setup APT proxy if provided
if [ -n "$APT_PROXY" ]; then
  # Basic URL validation
  if [[ ! "$APT_PROXY" =~ ^http://.* ]] && [[ ! "$APT_PROXY" =~ ^https://.* ]]; then
    echo "ERROR: Invalid APT proxy URL '$APT_PROXY'" >&2
    echo "URL must start with http:// or https://" >&2
    exit 1
  fi
  
  echo "APT proxy enabled: $APT_PROXY"
  export http_proxy="$APT_PROXY"
  export https_proxy="$APT_PROXY"
  export HTTP_PROXY="$APT_PROXY"
  export HTTPS_PROXY="$APT_PROXY"
fi

# Setup cache directories
CACHE_DIR="${REPO_ROOT}/.cache/distrobuilder"
SOURCES_CACHE="${CACHE_DIR}/sources"
MISE_CACHE="${CACHE_DIR}/mise"

setup_cache() {
  if [ "$CACHED" = true ]; then
    mkdir -p "${SOURCES_CACHE}"
    
    echo "Cache enabled:"
    echo "  Sources: ${SOURCES_CACHE} ($(du -sh ${SOURCES_CACHE} 2>/dev/null | cut -f1 || echo 'empty'))"
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
        --cache-dir "${SOURCES_CACHE}" \
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
  # For Proxmox compatibility, use rootfs.tar.xz directly (not wrapped)
  cp "${rootfs_tarball}" "${out_dir}/${artifact_name}"
  # Also include metadata for other uses
  cp "${meta_tarball}" "${out_dir}/${artifact_name%.tar.xz}.meta.tar.xz" 2>/dev/null || true

  cd "${out_dir}"
  sha256sum "${artifact_name}" > sha256sums.txt
  
  # Extract mise downloads from built image to populate cache
  if [ "$CACHED" = true ]; then
    echo "Extracting mise downloads from ${variant} build..."
    mkdir -p "${MISE_CACHE}"
    if tar -tf "${tmp_dir}/rootfs.tar.xz" 2>/dev/null | grep -q "usr/local/share/mise/downloads"; then
      # Extract to temp location first
      local extract_dir="${tmp_dir}/mise-extract"
      mkdir -p "${extract_dir}"
      tar -xf "${tmp_dir}/rootfs.tar.xz" -C "${extract_dir}" usr/local/share/mise/downloads/ 2>/dev/null || true
      
      # Move files to cache, merging with existing
      if [ -d "${extract_dir}/usr/local/share/mise/downloads" ]; then
        find "${extract_dir}/usr/local/share/mise/downloads" -type f -exec cp -v {} "${MISE_CACHE}/" \; 2>/dev/null || true
        echo "Updated mise cache: $(du -sh ${MISE_CACHE} 2>/dev/null | cut -f1)"
      fi
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
      echo "  Sources: $(du -sh ${SOURCES_CACHE} 2>/dev/null | cut -f1 || echo '0')"
      echo "  Mise:    $(du -sh ${MISE_CACHE} 2>/dev/null | cut -f1 || echo '0')"
      echo ""
      echo "Note: Downloads are cached after each successful build."
      echo "      Subsequent builds will be faster as cache grows."
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
