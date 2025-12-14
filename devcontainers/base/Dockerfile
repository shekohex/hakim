# syntax=docker/dockerfile:1.7

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
    build-essential gawk && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# =============================================================================
# Stage 2: Download external binaries (version-isolated)
# =============================================================================
FROM base-system AS tool-downloader

ARG TARGETARCH=amd64
ARG CODER_VERSION=2.21.0
ARG CODE_SERVER_VERSION=4.100.3
ARG OPENCODE_VERSION=0.3.7

WORKDIR /downloads

RUN curl -fsSL "https://github.com/coder/coder/releases/download/v${CODER_VERSION}/coder_${CODER_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xzf - ./coder

RUN curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH}.tar.gz" \
    | tar -xzf - && mv code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH} code-server

RUN curl -fsSL "https://github.com/sst/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
    | tar -xzf -

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

COPY --from=tool-downloader /downloads/coder /usr/local/bin/coder
COPY --from=tool-downloader /downloads/code-server /usr/local/lib/code-server
COPY --from=tool-downloader /downloads/opencode /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/coder /usr/local/bin/opencode && \
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
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

USER coder
