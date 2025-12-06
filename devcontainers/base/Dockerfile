FROM debian:bookworm-slim

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

# Create coder user
RUN useradd -m -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder
USER coder
