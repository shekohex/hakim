ARG BASE_IMAGE=ghcr.io/shekohex/hakim-base:latest
FROM ${BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-c"]
ENV MISE_YES=1

RUN chmod -R 777 /usr/local/share/mise

ARG NODE_VERSION=24.12.0
ARG NODE_GYP_VERSION=12.2.0
RUN source /etc/profile.d/mise.sh && \
  mise use --global node@${NODE_VERSION} && \
  export NPM_CONFIG_CACHE=/tmp/.npm && \
  npm install -g "node-gyp@${NODE_GYP_VERSION}" && \
  rm -rf /tmp/.npm /root/.npm && \
  for bin_path in $(mise bin-paths); do \
    for bin_file in "$bin_path"/*; do \
      if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then \
        ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"; \
      fi; \
    done; \
  done

ARG BUN_VERSION=1.3.5
RUN source /etc/profile.d/mise.sh && \
  mise use --global bun@${BUN_VERSION} && \
  for bin_path in $(mise bin-paths); do \
    for bin_file in "$bin_path"/*; do \
      if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then \
        ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"; \
      fi; \
    done; \
  done

ARG UV_VERSION=0.9.24
ARG UV_PYTHON_VERSION=3.12.12
RUN source /etc/profile.d/mise.sh && \
  mise use --global uv@${UV_VERSION} && \
  uv python install "${UV_PYTHON_VERSION}" && \
  for bin_path in $(mise bin-paths); do \
    for bin_file in "$bin_path"/*; do \
      if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then \
        ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"; \
      fi; \
    done; \
  done
