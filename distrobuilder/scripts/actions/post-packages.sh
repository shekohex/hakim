#!/bin/bash
set -euo pipefail

VARIANT=${1:-base}
ASSETS_DIR=/usr/local/share/hakim/assets
FEATURES_DIR=/usr/local/share/hakim/assets/features

CODER_VERSION=${CODER_VERSION:-2.29.5}
CODE_SERVER_VERSION=${CODE_SERVER_VERSION:-4.108.2}
DOCKER_CLI_VERSION=${DOCKER_CLI_VERSION:-28.3.3}
DOCKER_COMPOSE_VERSION=${DOCKER_COMPOSE_VERSION:-2.29.7}
GOOGLE_CHROME_VERSION=${GOOGLE_CHROME_VERSION:-143.0.7499.192-1}
GIT_SOURCE_TAG=${GIT_SOURCE_TAG:-v2.52.0}
NODE_VERSION=${NODE_VERSION:-24.12.0}
NODE_GYP_VERSION=${NODE_GYP_VERSION:-12.2.0}
BUN_VERSION=${BUN_VERSION:-1.3.5}
UV_VERSION=${UV_VERSION:-0.9.24}
UV_PYTHON_VERSION=${UV_PYTHON_VERSION:-3.12.12}

MISE_VERSION=${MISE_VERSION:-2026.2.1}
MISE_SHA256_X64=${MISE_SHA256_X64:-436d726c4046dd9e2681831830de5063c336d8a8164a9801de4c221bf5a8f846}
MISE_SHA256_ARM64=${MISE_SHA256_ARM64:-6726622825e5b79d4608e74f0ee5b4f1173c39ba3d0548e8d66dfeafdc4f46a0}

ARCH=$(dpkg --print-architecture)

case "${ARCH}" in
amd64)
  RELEASE_ARCH=amd64
  ;;
arm64)
  RELEASE_ARCH=arm64
  ;;
*)
  echo "Unsupported architecture: ${ARCH}" >&2
  exit 1
  ;;
esac

require_file() {
  if [ ! -f "$1" ]; then
    echo "Required file not found: $1" >&2
    exit 1
  fi
}

source_mise() {
  if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
  fi
}

link_mise_bins() {
  if ! command -v mise >/dev/null 2>&1; then
    return
  fi

  for bin_path in $(mise bin-paths); do
    if [ -d "${bin_path}" ]; then
      for bin_file in "${bin_path}"/*; do
        if [ -f "${bin_file}" ] && [ -x "${bin_file}" ]; then
          ln -sf "${bin_file}" "/usr/local/bin/$(basename "${bin_file}")"
        fi
      done
    fi
  done
}

install_git_credential_libsecret() {
  apt-get update
  apt-get install -y --no-install-recommends libsecret-1-dev libglib2.0-dev pkg-config make
  rm -rf /tmp/git-src
  git clone --depth 1 --branch "${GIT_SOURCE_TAG}" https://github.com/git/git /tmp/git-src
  make -C /tmp/git-src/contrib/credential/libsecret
  cp /tmp/git-src/contrib/credential/libsecret/git-credential-libsecret /usr/local/bin/git-credential-libsecret
  chmod +x /usr/local/bin/git-credential-libsecret
  rm -rf /tmp/git-src
}

install_docker_cli() {
  docker_arch="${ARCH}"
  tmp_tar="/tmp/docker-cli.tgz"
  curl -fsSL "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_CLI_VERSION}.tgz" -o "${tmp_tar}"
  tar -xzf "${tmp_tar}" -C /tmp
  cp /tmp/docker/docker /usr/local/bin/docker
  chmod +x /usr/local/bin/docker
  rm -rf /tmp/docker "${tmp_tar}"
}

install_docker_compose() {
  compose_arch=$(case "${ARCH}" in amd64) echo "x86_64" ;; arm64) echo "aarch64" ;; *) echo "${ARCH}" ;; esac)
  install -d /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}" -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
}

install_google_chrome() {
  if [ "${ARCH}" != "amd64" ]; then
    return
  fi

  tmp_deb="/tmp/google-chrome.deb"
  curl -fsSL "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${GOOGLE_CHROME_VERSION}_amd64.deb" -o "${tmp_deb}"
  dpkg -i "${tmp_deb}" || apt-get install -f -y
  rm -f "${tmp_deb}"
  printf '%s\n' "alias google-chrome=/usr/bin/google-chrome-stable" > /etc/profile.d/google-chrome.sh
}

install_mise() {
  require_file "${ASSETS_DIR}/install-mise.sh"
  chmod +x "${ASSETS_DIR}/install-mise.sh"

  MISE_VERSION="${MISE_VERSION}" MISE_SHA256_X64="${MISE_SHA256_X64}" MISE_SHA256_ARM64="${MISE_SHA256_ARM64}" \
    bash "${ASSETS_DIR}/install-mise.sh"

  require_file "${ASSETS_DIR}/mise.toml"
  install -d /etc/mise
  cp "${ASSETS_DIR}/mise.toml" /etc/mise/config.toml

  source_mise

  MISE_YES=1 mise install --yes

  if [ -x /etc/mise/tasks/postinstall ]; then
    chmod +x /etc/mise/tasks/*
    MISE_YES=1 mise run -C /etc/mise postinstall --yes
    rm -rf /etc/mise/tasks
  fi

  link_mise_bins
}

install_coder_cli() {
  tmp_tar="/tmp/coder.tar.gz"
  tmp_dir="/tmp/coder-extract"
  curl -fsSL "https://github.com/coder/coder/releases/download/v${CODER_VERSION}/coder_${CODER_VERSION}_linux_${RELEASE_ARCH}.tar.gz" -o "${tmp_tar}"
  rm -rf "${tmp_dir}"
  mkdir -p "${tmp_dir}"
  tar -xzf "${tmp_tar}" -C "${tmp_dir}"
  # Find and install the coder binary
  if [ -f "${tmp_dir}/coder" ]; then
    cp "${tmp_dir}/coder" /usr/local/bin/coder
  else
    # Try to find it in subdirectories
    coder_bin=$(find "${tmp_dir}" -name "coder" -type f -executable | head -1)
    if [ -n "${coder_bin}" ]; then
      cp "${coder_bin}" /usr/local/bin/coder
    else
      echo "ERROR: Could not find coder binary in tarball" >&2
      ls -la "${tmp_dir}"
      exit 1
    fi
  fi
  chmod +x /usr/local/bin/coder
  rm -rf "${tmp_tar}" "${tmp_dir}"
}

install_code_server() {
  tmp_tar="/tmp/code-server.tar.gz"
  curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${RELEASE_ARCH}.tar.gz" -o "${tmp_tar}"
  rm -rf /usr/local/lib/code-server
  mkdir -p /usr/local/lib
  tar -xzf "${tmp_tar}" -C /tmp
  mv "/tmp/code-server-${CODE_SERVER_VERSION}-linux-${RELEASE_ARCH}" /usr/local/lib/code-server
  ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
  rm -f "${tmp_tar}"
}

install_tooling_stack() {
  source_mise

  MISE_YES=1 mise use --global node@"${NODE_VERSION}"
  export NPM_CONFIG_CACHE=/tmp/.npm
  npm install -g "node-gyp@${NODE_GYP_VERSION}"
  rm -rf /tmp/.npm /root/.npm /home/coder/.npm

  MISE_YES=1 mise use --global bun@"${BUN_VERSION}"
  MISE_YES=1 mise use --global uv@"${UV_VERSION}"
  uv python install "${UV_PYTHON_VERSION}"

  link_mise_bins
}

install_php_stack() {
  codename=$(awk -F= '$1=="VERSION_CODENAME" {print $2}' /etc/os-release)
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg2
  install -d /etc/apt/keyrings
  curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/keyrings/sury-php.gpg
  chmod 0644 /etc/apt/keyrings/sury-php.gpg
  echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${codename} main" > /etc/apt/sources.list.d/sury-php.list
  apt-get update
  apt-get install -y --no-install-recommends php8.4-cli php8.4-curl php8.4-mbstring php8.4-xml php8.4-zip composer
  update-alternatives --set php /usr/bin/php8.4 || true

  require_file "${FEATURES_DIR}/laravel-install.sh"
  VERSION=5.24.3 TOOLS="" bash "${FEATURES_DIR}/laravel-install.sh"
}

install_dotnet_stack() {
  curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb
  dpkg -i /tmp/packages-microsoft-prod.deb
  rm -f /tmp/packages-microsoft-prod.deb
  apt-get update
  if ! apt-get install -y --no-install-recommends dotnet-sdk-9.0 dotnet-sdk-10.0; then
    apt-get install -y --no-install-recommends dotnet-sdk-9.0
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 10.0 --quality preview --install-dir /usr/local/share/dotnet
    ln -sf /usr/local/share/dotnet/dotnet /usr/local/bin/dotnet
    rm -f /tmp/dotnet-install.sh
  fi
}

install_rust_stack() {
  source_mise
  MISE_YES=1 mise use --global rust@1.93.0
  link_mise_bins
}

install_elixir_stack() {
  require_file "${FEATURES_DIR}/elixir-install.sh"
  require_file "${FEATURES_DIR}/phoenix-install.sh"
  require_file "${FEATURES_DIR}/postgresql-tools-install.sh"

  ERLANG_VERSION=27 ELIXIR_VERSION=1.17 SEEDUSERHOME=true _REMOTE_USER=coder bash "${FEATURES_DIR}/elixir-install.sh"
  VERSION=1.8.3 SEEDUSERHOME=true _REMOTE_USER=coder bash "${FEATURES_DIR}/phoenix-install.sh"
  VERSION=17 bash "${FEATURES_DIR}/postgresql-tools-install.sh"
}

install_lazyvim() {
  require_file "${FEATURES_DIR}/lazyvim-install.sh"
  _REMOTE_USER=coder bash "${FEATURES_DIR}/lazyvim-install.sh"
}

install_mise
install_coder_cli
install_code_server
install_git_credential_libsecret
install_docker_cli
install_docker_compose
install_google_chrome

case "${VARIANT}" in
base)
  ;;
js)
  install_tooling_stack
  install_lazyvim
  ;;
php)
  install_tooling_stack
  install_php_stack
  install_lazyvim
  ;;
dotnet)
  install_tooling_stack
  install_dotnet_stack
  install_lazyvim
  ;;
rust)
  install_tooling_stack
  install_rust_stack
  install_lazyvim
  ;;
elixir)
  install_tooling_stack
  install_elixir_stack
  install_lazyvim
  ;;
*)
  echo "Unknown variant '${VARIANT}'" >&2
  exit 1
  ;;
esac

link_mise_bins
