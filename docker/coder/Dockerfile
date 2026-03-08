ARG CODER_VERSION
FROM ghcr.io/coder/coder:v${CODER_VERSION}

USER root

RUN apk add --no-cache \
  age \
  jq

USER 1000:1000
