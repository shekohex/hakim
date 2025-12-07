FROM debian:trixie-slim

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install common dependencies
RUN apt-get update && apt-get upgrade --yes --no-install-recommends --no-install-suggests \
    && apt-get install -y \
    curl wget jq unzip sudo bash htop locales vim \
    ca-certificates gnupg lsb-release git \
    && rm -rf /var/lib/apt/lists/*

# Generate the desired locale (en_US.UTF-8)
RUN locale-gen en_US.UTF-8

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

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
RUN useradd -m -s /bin/bash coder --groups=docker --user-group --uid=1000 \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder
USER coder
