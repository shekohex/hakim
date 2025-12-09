FROM debian:trixie-slim

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install common dependencies
RUN apt-get update && apt-get upgrade --yes --no-install-recommends --no-install-suggests \
    && apt-get install -y \
    curl wget jq unzip sudo bash htop locales \
    ca-certificates gnupg lsb-release git lsof \
    build-essential

# Generate the desired locale (en_US.UTF-8)
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Docker (client only, host docker socket will be mounted)
COPY --from=docker:dind /usr/local/bin/docker /usr/local/bin/

# Install Mise
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    PATH="/usr/local/share/mise/shims:$PATH"
RUN mkdir -p /usr/local/share/mise /etc/mise && chmod -R 777 /usr/local/share/mise && chmod -R 755 /etc/mise
COPY install-mise.sh /tmp/install-mise.sh
RUN bash /tmp/install-mise.sh && rm /tmp/install-mise.sh

# Configure Mise and install tools
COPY mise.toml /etc/mise/config.toml
COPY tasks /etc/mise/tasks
RUN --mount=type=secret,id=github_token \
    if [ -f /run/secrets/github_token ]; then export GITHUB_TOKEN=$(cat /run/secrets/github_token); fi \
    && /usr/local/bin/mise install --yes \
    && /usr/local/bin/mise run -C /etc/mise postinstall --yes \
    && rm -rf /etc/mise/tasks


# Pre-download coder CLI binary to avoid runtime download
ARG CODER_VERSION=2.29.0
ARG TARGETARCH=amd64
RUN curl -fsSL "https://github.com/coder/coder/releases/download/v${CODER_VERSION}/coder_${CODER_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xzf - -C /tmp && mv /tmp/coder /usr/local/bin/coder && chmod +x /usr/local/bin/coder

# Install code-server
ARG CODE_SERVER_VERSION=4.106.3
RUN curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH}.tar.gz" \
    | tar -xzf - -C /tmp && mv /tmp/code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH} /usr/local/lib/code-server \
    && ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

# Install opencode
ARG OPENCODE_VERSION=latest
RUN if [ "$OPENCODE_VERSION" = "latest" ]; then \
    curl -fsSL https://opencode.ai/install | bash; \
    else \
    VERSION=$OPENCODE_VERSION curl -fsSL https://opencode.ai/install | bash; \
    fi
# Move opencode to global path
RUN mv /root/.opencode/bin/opencode /usr/local/bin/opencode

# Create coder user
RUN groupadd -f docker \
    && useradd -m -s /bin/bash coder --groups=docker --user-group --uid=1000 \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder
USER coder
