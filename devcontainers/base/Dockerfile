# syntax=docker/dockerfile:1.7

# =============================================================================
# Caching guidelines
# - Keep version ARGs scoped to the stage that uses them.
# - Split external downloads into independent stages.
# - Avoid touching Stage 1 unless absolutely needed.
# - Prefer adding new stages over modifying shared ones.
# =============================================================================

# =============================================================================
# Stage 1: Base system packages (rarely changes)
# =============================================================================
FROM debian:trixie-slim AS base-system

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  rm -f /etc/apt/apt.conf.d/docker-clean && \
  apt-get update && apt-get install -y --no-install-recommends \
  curl wget jq unzip sudo bash htop locales \
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
ARG CODER_VERSION=2.28.9
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
ARG CODE_SERVER_VERSION=4.108.2
# VERSION_UPDATE_END: code-server

WORKDIR /downloads

RUN curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH}.tar.gz" \
  | tar -xzf - && mv code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH} code-server

# =============================================================================
# Stage 2c: Download opencode (version-isolated)
# =============================================================================
FROM base-system AS opencode-downloader

# VERSION_UPDATE_BEGIN: opencode
ARG OPENCODE_VERSION=1.1.47
# VERSION_UPDATE_END: opencode

WORKDIR /downloads

RUN curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
  | tar -xzf -

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
# Stage 2e: Download Google Chrome (version-isolated)
# =============================================================================
FROM base-system AS chrome-downloader

ARG GOOGLE_CHROME_VERSION=143.0.7499.192-1

WORKDIR /downloads

RUN wget -q "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${GOOGLE_CHROME_VERSION}_amd64.deb" -O google-chrome.deb

# =============================================================================
# Stage 3: Install mise + tools (config-isolated)
# =============================================================================
FROM base-system AS mise-installer

ENV MISE_DATA_DIR=/usr/local/share/mise \
  MISE_CONFIG_DIR=/etc/mise \
  PATH="/usr/local/share/mise/shims:$PATH"

RUN mkdir -p /usr/local/share/mise /etc/mise && chmod -R 777 /usr/local/share/mise

COPY install-mise.sh /tmp/
RUN bash /tmp/install-mise.sh && rm /tmp/install-mise.sh

COPY mise.toml /etc/mise/config.toml
RUN --mount=type=secret,id=github_token \
  if [ -f /run/secrets/github_token ]; then export GITHUB_TOKEN=$(cat /run/secrets/github_token); fi && \
  /usr/local/bin/mise install --yes

# =============================================================================
# Final Stage: Assemble everything
# =============================================================================
FROM base-system AS final

ENV MISE_DATA_DIR=/usr/local/share/mise \
  MISE_CONFIG_DIR=/etc/mise \
  PATH="/usr/local/share/mise/shims:$PATH" \
  STARSHIP_CONFIG=/etc/starship.toml

COPY --from=docker:dind /usr/local/bin/docker /usr/local/bin/
COPY --from=docker-compose-downloader /downloads/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

COPY --from=chrome-downloader /downloads/google-chrome.deb /tmp/google-chrome.deb
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  dpkg -i /tmp/google-chrome.deb || apt --fix-broken install -y && \
  rm /tmp/google-chrome.deb

COPY --from=coder-downloader /downloads/coder /usr/local/bin/coder
COPY --from=code-server-downloader /downloads/code-server /usr/local/lib/code-server
COPY --from=opencode-downloader /downloads/opencode /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/coder /usr/local/bin/opencode && \
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
  ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose && \
  ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

COPY --from=mise-installer /usr/local/bin/mise /usr/local/bin/mise
COPY --from=mise-installer /usr/local/share/mise /usr/local/share/mise
COPY --from=mise-installer /etc/profile.d/mise.sh /etc/profile.d/mise.sh

RUN mkdir -p /etc/mise
COPY mise.toml /etc/mise/config.toml
COPY starship.toml /etc/starship.toml
COPY tasks /etc/mise/tasks

RUN --mount=type=secret,id=github_token \
  if [ -f /run/secrets/github_token ]; then export GITHUB_TOKEN=$(cat /run/secrets/github_token); fi && \
  /usr/local/bin/mise run -C /etc/mise postinstall --yes && \
  rm -rf /etc/mise/tasks

RUN groupadd -f docker && \
  useradd -m -s /bin/bash coder --groups=docker --user-group --uid=1000 && \
  echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder && \
  echo 'alias google-chrome=/usr/bin/google-chrome-stable' > /etc/profile.d/google-chrome.sh

USER coder
