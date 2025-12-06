FROM debian:trixie-slim

# Install common dependencies
RUN apt-get update && apt-get install -y \
    curl wget git jq unzip sudo \
    ca-certificates gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker (client only, host docker socket will be mounted)
COPY --from=docker:dind /usr/local/bin/docker /usr/local/bin/

# Install Mise
COPY install-mise.sh /tmp/install-mise.sh
RUN bash /tmp/install-mise.sh && rm /tmp/install-mise.sh

# Pre-download coder CLI binary to avoid runtime download
ARG CODER_VERSION=2.29.0
ARG TARGETARCH=amd64
RUN curl -fsSL "https://github.com/coder/coder/releases/download/v${CODER_VERSION}/coder_${CODER_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xzf - -C /tmp && mv /tmp/coder /usr/local/bin/coder && chmod +x /usr/local/bin/coder

# Create coder user
RUN useradd -m -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder
USER coder
