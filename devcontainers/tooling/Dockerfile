ARG BASE_IMAGE=ghcr.io/shekohex/hakim-base:latest
FROM ${BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-c"]
ENV MISE_YES=1

RUN chmod -R 777 /usr/local/share/mise

ARG NODE_VERSION=24.12.0
ARG NODE_GYP_VERSION=12.2.0
RUN export MISE_DATA_DIR=/usr/local/share/mise MISE_CONFIG_DIR=/etc/mise MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml && source /etc/profile.d/mise.sh && \
  mise use --global node@${NODE_VERSION} && \
  export NPM_CONFIG_CACHE=/tmp/.npm && \
  npm install -g "node-gyp@${NODE_GYP_VERSION}" && \
  rm -rf /tmp/.npm /root/.npm

ARG BUN_VERSION=1.3.5
RUN export MISE_DATA_DIR=/usr/local/share/mise MISE_CONFIG_DIR=/etc/mise MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml && source /etc/profile.d/mise.sh && \
  mise use --global bun@${BUN_VERSION}

# VERSION_UPDATE_BEGIN: opencode
ARG OPENCODE_VERSION=1.2.5
# VERSION_UPDATE_END: opencode
RUN su coder -s /bin/bash -c "HOME=/home/coder NPM_CONFIG_PREFIX=/home/coder/.npm-global MISE_INSTALL_PATH=/usr/local/bin/mise PATH=/usr/local/bin:/usr/local/share/mise/installs/node/${NODE_VERSION}/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin /usr/local/share/mise/installs/node/${NODE_VERSION}/bin/npm install -g opencode-ai@${OPENCODE_VERSION}" && \
  ln -sf /home/coder/.npm-global/bin/opencode /usr/local/bin/opencode

ARG UV_VERSION=0.9.24
ARG UV_PYTHON_VERSION=3.12.12
RUN export MISE_DATA_DIR=/usr/local/share/mise MISE_CONFIG_DIR=/etc/mise MISE_GLOBAL_CONFIG_FILE=/etc/mise/tools.toml && source /etc/profile.d/mise.sh && \
  mise use --global uv@${UV_VERSION} && \
  uv python install "${UV_PYTHON_VERSION}"

RUN for bin in node npm npx corepack pnpm yarn bun uv uvx; do \
  path="/usr/local/bin/${bin}"; \
  if [ -L "$path" ]; then \
    target="$(readlink -f "$path" 2>/dev/null || true)"; \
    case "$target" in \
      /usr/local/share/mise/installs/*/bin/*) rm -f "$path" ;; \
    esac; \
  fi; \
done

RUN rm -f /etc/mise/tools.toml && printf "[settings]\nexperimental = true\n" > /etc/mise/config.toml
