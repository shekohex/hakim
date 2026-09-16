# syntax=docker/dockerfile:1.7
#
# CubeSandbox runtime adapter for Hakim language images.
#
# Layering contract:
#   * `cubesandbox-runtime` only carries envd, the upstream entrypoint and the
#     envd reference file from the pinned official CubeSandbox base image, so
#     that tag+digest stays the single source of truth for the Cube data plane.
#   * The final stage is the existing `hakim-<variant>` image with those files,
#     tini and the Xvfb/Vulkan packages added. No other Hakim layers change, so
#     built cube images share every heavy layer with their Hakim counterpart.
#
# Build (see scripts/build-cube-images.sh):
#   docker buildx build --load \
#     --build-arg HAKIM_IMAGE=ghcr.io/shekohex/hakim-js:<immutable-tag> \
#     --build-arg HAKIM_VARIANT=js \
#     -t ghcr.io/shekohex/cube-hakim-js:<immutable-tag> \
#     devcontainers/cube

ARG CUBESANDBOX_BASE=ghcr.io/tencentcloud/cubesandbox-base:2026.16@sha256:a1dd972a4eef85448f967daed3bda42c6be2b7f42bf64c1f4d38e63b3e935472
ARG HAKIM_IMAGE=registry.invalid/hakim-image:override-required

FROM ${CUBESANDBOX_BASE} AS cubesandbox-runtime

FROM ${HAKIM_IMAGE}

ARG HAKIM_VARIANT=unknown
ARG HAKIM_COMMIT=unknown
# Docker does not carry the global ARG default into a stage, and the base ref is
# needed for the OCI label. Keep this in sync with CUBESANDBOX_BASE above.
ARG CUBESANDBOX_BASE=ghcr.io/tencentcloud/cubesandbox-base:2026.16@sha256:a1dd972a4eef85448f967daed3bda42c6be2b7f42bf64c1f4d38e63b3e935472

USER root
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# tini is PID 1. The Hakim base already ships Xvfb and Vulkan support. zip and
# rsync complete the always-baked repository primitives.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    tini \
    zip \
    rsync && \
  rm -rf /var/lib/apt/lists/* && \
  test "$(dpkg-query -W -f='${Status}\n' tini zip rsync | grep -c 'install ok installed')" = "3"

COPY --from=cubesandbox-runtime /usr/bin/envd /usr/bin/envd
COPY --from=cubesandbox-runtime /usr/local/bin/cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh
COPY --from=cubesandbox-runtime /etc/cubesandbox-envd-ref /etc/cubesandbox-envd-ref
COPY entrypoint.sh /usr/local/bin/hakim-cube-entrypoint

RUN chmod 0755 /usr/bin/envd /usr/local/bin/cube-entrypoint.sh /usr/local/bin/hakim-cube-entrypoint && \
  install -d -m 0755 /var/log

ENV ENVD_PORT=49983 \
    DISPLAY=:99 \
    LIBGL_ALWAYS_SOFTWARE=1

EXPOSE 49983

LABEL org.opencontainers.image.title="cube-hakim-${HAKIM_VARIANT}" \
      org.opencontainers.image.description="Hakim ${HAKIM_VARIANT} toolchain with the CubeSandbox envd runtime" \
      org.opencontainers.image.source="https://github.com/shekohex/hakim" \
      org.opencontainers.image.revision="${HAKIM_COMMIT}" \
      io.hakim.variant="${HAKIM_VARIANT}" \
      io.hakim.cube.base="${CUBESANDBOX_BASE}"

# Reset the inherited Hakim startup path: tini reaps, the supervisor starts
# Docker + Xvfb, then hands the envd/application lifecycle to the upstream
# CubeSandbox entrypoint.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hakim-cube-entrypoint"]
CMD []
