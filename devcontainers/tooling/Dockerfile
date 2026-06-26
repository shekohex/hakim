# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ghcr.io/shekohex/hakim-base:latest
FROM ${BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-c"]
ENV MISE_YES=1

RUN chmod -R 777 /usr/local/share/mise

ARG NODE_VERSION=24.12.0
ARG NODE_GYP_VERSION=12.2.0
RUN --mount=type=cache,target=/root/.cache/mise,sharing=locked \
  export MISE_DATA_DIR=/usr/local/share/mise \
  MISE_CONFIG_DIR=/etc/mise \
  MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml && \
  mise use --global node@${NODE_VERSION} && \
  export NPM_CONFIG_CACHE=/tmp/.npm && \
  success=0 && \
  for attempt in 1 2 3 4 5; do \
    if npm install -g "node-gyp@${NODE_GYP_VERSION}"; then success=1; break; fi; \
    npm cache clean --force >/dev/null 2>&1 || true; \
    sleep "$((attempt * 2))"; \
  done && \
  [ "$success" -eq 1 ] && \
  rm -rf /tmp/.npm /root/.npm

ARG BUN_VERSION=1.3.9
RUN --mount=type=cache,target=/root/.cache/mise,sharing=locked \
  export MISE_DATA_DIR=/usr/local/share/mise \
  MISE_CONFIG_DIR=/etc/mise \
  MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml && \
  mise use --global bun@${BUN_VERSION}

ARG UV_VERSION=0.9.24
ARG UV_PYTHON_VERSION=3.12.12
RUN --mount=type=cache,target=/root/.cache/mise,sharing=locked \
  --mount=type=cache,target=/root/.cache/uv,sharing=locked \
  export MISE_DATA_DIR=/usr/local/share/mise \
  MISE_CONFIG_DIR=/etc/mise \
  MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml && \
  mise use --global uv@${UV_VERSION} && \
  uv python install "${UV_PYTHON_VERSION}" && \
  uv python list

RUN /usr/local/bin/hakim-expose-mise-tools

RUN printf "[settings]\nexperimental = true\n" > /etc/mise/config.toml

RUN rm -rf /root/.cache/mise /root/.cache/uv /usr/local/share/mise/cache /usr/local/share/mise/downloads
