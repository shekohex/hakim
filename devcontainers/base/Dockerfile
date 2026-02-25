# syntax=docker/dockerfile:1.7

# =============================================================================
# Caching guidelines
# - Keep version ARGs scoped to the stage that uses them.
# - Split external downloads into independent stages.
# - Avoid touching Stage 1 unless absolutely needed.
# - Prefer adding new stages over modifying shared ones.
# =============================================================================

ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:f6e2cfac5cf956ea044b4bd75e6397b4372ad88fe00908045e9a0d21712ae3ba
ARG DEBIAN_SNAPSHOT=20260201T000000Z
ARG DOCKER_CLI_IMAGE=docker:28.3.3-cli@sha256:0135662b510037ea581d99c2e5929c5e01185139c0b86986a418bd4da0b98a44

# =============================================================================
# Stage 1: Base system packages (rarely changes)
# =============================================================================
FROM ${DEBIAN_IMAGE} AS base-system

ARG DEBIAN_SNAPSHOT

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  rm -f /etc/apt/apt.conf.d/docker-clean && \
  rm -f /etc/apt/sources.list.d/*.sources && \
  echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot && \
  printf "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ trixie main\n" > /etc/apt/sources.list && \
  printf "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ trixie-updates main\n" >> /etc/apt/sources.list && \
  printf "deb http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/ trixie-security main\n" >> /etc/apt/sources.list && \
  apt-get update && apt-get install -y --no-install-recommends \
  curl wget jq unzip sudo bash bash-completion htop locales \
  ca-certificates gnupg lsb-release git lsof \
  build-essential gawk procps openssh-client && \
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
  LANGUAGE=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8

# =============================================================================
# Stage 2a: Download coder (version-isolated)
# =============================================================================
FROM base-system AS coder-downloader

ARG TARGETARCH=amd64
# VERSION_UPDATE_BEGIN: coder
ARG CODER_VERSION=2.29.7
# VERSION_UPDATE_END: coder

WORKDIR /downloads

RUN curl -fsSL "https://github.com/coder/coder/releases/download/v${CODER_VERSION}/coder_${CODER_VERSION}_linux_${TARGETARCH}.tar.gz" \
  | tar -xzf - ./coder

# =============================================================================
# Stage 2b: Download code-server (version-isolated)
# =============================================================================
FROM base-system AS code-server-downloader

ARG TARGETARCH=amd64
# VERSION_UPDATE_BEGIN: code-server
ARG CODE_SERVER_VERSION=4.109.2
# VERSION_UPDATE_END: code-server

WORKDIR /downloads

RUN curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH}.tar.gz" \
  | tar -xzf - && mv code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH} code-server

FROM base-system AS git-credential-libsecret-builder

ARG GIT_SOURCE_TAG=v2.52.0

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && apt-get install -y --no-install-recommends \
  libsecret-1-dev libglib2.0-dev pkg-config && \
  rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "$GIT_SOURCE_TAG" https://github.com/git/git /tmp/git-src && \
  make -C /tmp/git-src/contrib/credential/libsecret && \
  cp /tmp/git-src/contrib/credential/libsecret/git-credential-libsecret /tmp/

# =============================================================================
# Stage 2d: Download docker-compose (version-isolated)
# =============================================================================
FROM base-system AS docker-compose-downloader

ARG TARGETARCH=amd64
ARG DOCKER_COMPOSE_VERSION=2.29.7

WORKDIR /downloads

RUN ARCH=$(case ${TARGETARCH} in amd64) echo "x86_64" ;; arm64) echo "aarch64" ;; *) echo "${TARGETARCH}" ;; esac) && \
  curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o docker-compose

# =============================================================================
# Stage 2e: Download docker-buildx (version-isolated)
# =============================================================================
FROM base-system AS docker-buildx-downloader

ARG TARGETARCH=amd64
ARG DOCKER_BUILDX_VERSION=0.29.1

WORKDIR /downloads

RUN ARCH=$(case ${TARGETARCH} in amd64) echo "amd64" ;; arm64) echo "arm64" ;; *) echo "${TARGETARCH}" ;; esac) && \
  curl -fsSL "https://github.com/docker/buildx/releases/download/v${DOCKER_BUILDX_VERSION}/buildx-v${DOCKER_BUILDX_VERSION}.linux-${ARCH}" -o docker-buildx

# =============================================================================
# Stage 2f: Download Chrome for Testing (version-isolated)
# =============================================================================
FROM base-system AS chrome-for-testing-downloader

ARG TARGETARCH=amd64
# VERSION_UPDATE_BEGIN: chrome
ARG GOOGLE_CHROME_VERSION=145.0.7632.117
# VERSION_UPDATE_END: chrome

WORKDIR /downloads

RUN CFT_VERSION="${GOOGLE_CHROME_VERSION%%-*}" && \
  CFT_PLATFORM=$(case "${TARGETARCH}" in amd64) echo "linux64" ;; *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; esac) && \
  curl -fsSL "https://storage.googleapis.com/chrome-for-testing-public/${CFT_VERSION}/${CFT_PLATFORM}/chrome-${CFT_PLATFORM}.zip" -o chrome-linux64.zip && \
  curl -fsSL "https://storage.googleapis.com/chrome-for-testing-public/${CFT_VERSION}/${CFT_PLATFORM}/chromedriver-${CFT_PLATFORM}.zip" -o chromedriver-linux64.zip

FROM ${DOCKER_CLI_IMAGE} AS docker-cli

# =============================================================================
# Stage 3: Install mise + tools (config-isolated)
# =============================================================================
FROM base-system AS mise-installer

ARG MISE_VERSION=2026.2.1
ARG MISE_SHA256_X64=436d726c4046dd9e2681831830de5063c336d8a8164a9801de4c221bf5a8f846
ARG MISE_SHA256_ARM64=6726622825e5b79d4608e74f0ee5b4f1173c39ba3d0548e8d66dfeafdc4f46a0

ENV MISE_DATA_DIR=/usr/local/share/mise \
  MISE_CONFIG_DIR=/etc/mise \
  PATH="/usr/local/share/mise/shims:$PATH"

RUN mkdir -p /usr/local/share/mise /etc/mise && chmod -R 777 /usr/local/share/mise

COPY install-mise.sh /tmp/
RUN MISE_VERSION=${MISE_VERSION} MISE_SHA256_X64=${MISE_SHA256_X64} MISE_SHA256_ARM64=${MISE_SHA256_ARM64} bash /tmp/install-mise.sh && rm /tmp/install-mise.sh

COPY mise.toml /etc/mise/config.toml
RUN --mount=type=cache,target=/root/.cache/mise,sharing=locked \
  --mount=type=secret,id=github_token \
  if [ -f /run/secrets/github_token ]; then export GITHUB_TOKEN=$(cat /run/secrets/github_token); fi && \
  /usr/local/bin/mise install --yes

# =============================================================================
# Final Stage: Assemble everything
# =============================================================================
FROM base-system AS final

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/share/mise/shims" \
  STARSHIP_CONFIG=/etc/starship.toml

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/
COPY --from=docker-compose-downloader /downloads/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
COPY --from=docker-buildx-downloader /downloads/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=bind,from=chrome-for-testing-downloader,source=/downloads/chrome-linux64.zip,target=/tmp/chrome-linux64.zip \
  --mount=type=bind,from=chrome-for-testing-downloader,source=/downloads/chromedriver-linux64.zip,target=/tmp/chromedriver-linux64.zip \
  unzip -q /tmp/chrome-linux64.zip -d /opt && \
  unzip -q /tmp/chromedriver-linux64.zip -d /opt && \
  ln -sf /opt/chrome-linux64/chrome /usr/bin/google-chrome-stable && \
  ln -sf /opt/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver && \
  chmod +x /opt/chrome-linux64/chrome /usr/local/bin/chromedriver

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  select_package() { for pkg in "$@"; do if apt-cache show "$pkg" >/dev/null 2>&1; then echo "$pkg"; return 0; fi; done; return 1; } && \
  apt_packages=( \
    ca-certificates docker.io fonts-liberation libsecret-1-0 xdg-utils \
    libc6 libcairo2 libcups2 libdbus-1-3 libdrm2 libexpat1 libfontconfig1 \
    libgbm1 libgcc-s1 libgdk-pixbuf-2.0-0 libnspr4 libnss3 libstdc++6 libu2f-udev \
    libvulkan1 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 \
    libxext6 libxfixes3 libxi6 libxkbcommon0 libxrandr2 libxrender1 libxshmfence1 \
    libxss1 libxtst6 \
  ) && \
  apt_packages+=("$(select_package libasound2t64 libasound2)") && \
  apt_packages+=("$(select_package libatk-bridge2.0-0t64 libatk-bridge2.0-0)") && \
  apt_packages+=("$(select_package libatk1.0-0t64 libatk1.0-0)") && \
  apt_packages+=("$(select_package libglib2.0-0t64 libglib2.0-0)") && \
  apt_packages+=("$(select_package libpango-1.0-0t64 libpango-1.0-0)") && \
  apt-get install -y --no-install-recommends "${apt_packages[@]}" && \
  rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  install -d -m 0755 /etc/apt/keyrings && \
  curl -fsSL https://github.com/MisterTea/debian-et/raw/master/et.gpg -o /etc/apt/keyrings/et.gpg && \
  . /etc/os-release && \
  echo "deb [signed-by=/etc/apt/keyrings/et.gpg] https://mistertea.github.io/debian-et/debian-source/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/et.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends et openssh-server && \
  rm -rf /var/lib/apt/lists/*

COPY --from=coder-downloader /downloads/coder /usr/local/bin/coder
COPY --from=code-server-downloader /downloads/code-server /usr/local/lib/code-server
COPY --from=git-credential-libsecret-builder /tmp/git-credential-libsecret /usr/local/bin/git-credential-libsecret
RUN chmod +x /usr/local/bin/coder /usr/local/bin/git-credential-libsecret && \
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
  chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx && \
  ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose && \
  ln -s /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/bin/docker-buildx && \
  ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

COPY --from=mise-installer /usr/local/bin/mise /usr/local/bin/mise
COPY --from=mise-installer /usr/local/share/mise /usr/local/share/mise
COPY --from=mise-installer /etc/profile.d/mise.sh /etc/profile.d/mise.sh

RUN mkdir -p /etc/mise && printf "[settings]\nexperimental = true\n" > /etc/mise/config.toml
COPY mise.toml /etc/mise/tools.toml
COPY starship.toml /etc/starship.toml
COPY tasks /etc/mise/tasks

RUN --mount=type=cache,target=/root/.cache/mise,sharing=locked \
  --mount=type=secret,id=github_token \
  if [ -f /run/secrets/github_token ]; then export GITHUB_TOKEN=$(cat /run/secrets/github_token); fi && \
  MISE_DATA_DIR=/usr/local/share/mise MISE_CONFIG_DIR=/etc/mise MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml /usr/local/bin/mise run -C /etc/mise postinstall --yes && \
  rm -rf /etc/mise/tasks /usr/local/share/mise/cache /usr/local/share/mise/downloads

RUN groupadd -f docker && \
  useradd -m -s /bin/bash coder --groups=docker --user-group --uid=1000 && \
  echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder && \
  echo 'alias google-chrome=/usr/bin/google-chrome-stable' > /etc/profile.d/google-chrome.sh

COPY entrypoint.sh /usr/local/bin/hakim-entrypoint
RUN chmod +x /usr/local/bin/hakim-entrypoint

ENTRYPOINT ["/usr/local/bin/hakim-entrypoint"]
CMD ["bash"]
