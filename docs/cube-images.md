# CubeSandbox Images

Hakim also publishes CubeSandbox-compatible images: `cube-hakim-<variant>`.
They are the normal `hakim-<variant>` images plus the CubeSandbox data plane
(`envd`), tini, Vulkan packages, and supervisor. They use the Xvfb packages
already present in Hakim's base image. Coder templates and workflows keep using
the unchanged `hakim-*` images.

## Architecture

```text
ghcr.io/tencentcloud/cubesandbox-base:<tag>@<digest>   (pinned)
  └── cubesandbox-runtime       only envd, cube-entrypoint.sh, envd ref file
        │
hakim-base → hakim-tooling → hakim-<variant>
        └── cube-hakim-<variant>   hakim-<variant> + Cube runtime layer
```

The adapter (`devcontainers/cube/Dockerfile`) starts `FROM <pinned cube base>`
purely to harvest three files with `COPY --from`, then builds the final stage
`FROM ${HAKIM_IMAGE}`. Every heavy layer is therefore shared with the matching
`hakim-<variant>` image; the cube layer only adds `envd`, `tini`, the Cube-only
packages below, and the entrypoint.

| Added by the cube layer | Source |
| :--- | :--- |
| `/usr/bin/envd` | pinned CubeSandbox base |
| `/usr/local/bin/cube-entrypoint.sh` | pinned CubeSandbox base |
| `/etc/cubesandbox-envd-ref` | pinned CubeSandbox base |
| `tini`, `zip`, `rsync` | Debian (variant image) |
| `/usr/local/bin/hakim-cube-entrypoint` | `devcontainers/cube/entrypoint.sh` |

### Image contract

- `ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hakim-cube-entrypoint"]`
- `CMD []` — the inherited Hakim `CMD ["bash"]` is reset; with no command the
  upstream entrypoint keeps `envd` as the foreground process.
- `ENV ENVD_PORT=49983 DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1`
- `EXPOSE 49983`
- Final user stays `root`; `coder` remains UID/GID 1000 and is a member of
  `docker`. Cube SDK operations run as `root` when no user is supplied; callers
  must explicitly request `user=coder` when they want UID/GID 1000.
- OCI labels record the Hakim variant, revision and cube base ref. The
  authoritative envd reference remains `/etc/cubesandbox-envd-ref` copied from
  the pinned base image; no synthetic label is emitted for it. No credentials,
  auth files, repository data or user state are baked.

## Service lifecycle

`hakim-cube-entrypoint` is the only child of `tini` (PID 1). It starts the
minimum set of services, in this order, and only then hands over to the upstream
entrypoint:

1. **Docker daemon** — sandbox-local `--data-root` (default `/var/lib/docker`),
   stale pid/socket files removed first, storage drivers attempted in order
   `overlay2 → fuse-overlayfs → vfs`, then each driver is retried with
   `--iptables=false` for microVM kernels without netfilter. `docker info` (not
   just `--version`) must succeed before continuing.
2. **Xvfb** — `Xvfb :99 -screen 0 $XVFB_SCREEN -nolisten tcp`, then poll
   `xdpyinfo -display :99` until the display answers.
3. **Upstream `cube-entrypoint.sh`** — starts `envd` on `:49983` and keeps it as
   the foreground process, or runs a user command if one is supplied.

Because `envd` only starts after Docker and Xvfb are ready, a `2xx` from
`:49983/health` (the Cube template readiness probe) also means the display and
Docker are usable when the template snapshot is taken.

Shutdown:

- `SIGTERM`/`SIGINT`/`SIGHUP` are forwarded to the entrypoint session so `envd`,
  applications and Chrome stop together.
- Docker is stopped next (dockerd terminates its child containers), then Xvfb.
- Each service runs in its own session/process group; a group that does not exit
  within its timeout is `SIGKILL`ed. Session leaders are `wait`ed on so no
  zombies remain. The supervisor does not use global name-based process kills,
  which could terminate workload-owned Chrome or containerd processes.

Useful overrides: `DOCKER_DATA_ROOT`, `DOCKER_STORAGE_DRIVERS`,
`DOCKERD_EXTRA_ARGS`, `DOCKER_START_TIMEOUT`, `DOCKER_STOP_TIMEOUT`,
`XVFB_SCREEN`, `XVFB_READY_TIMEOUT`, `SERVICE_STOP_TIMEOUT`,
`HAKIM_CUBE_STRICT_RUNTIME` (default `true`; set `false` to boot even if Docker
or Xvfb fails).

## Build and publish

Keep the CubeSandbox base tag and digest pinned in `devcontainers/cube/Dockerfile`.

```bash
# Immutable Cube tag generated from commit + UTC timestamp, loaded locally.
# The source Hakim tag/ref is explicit and must already exist.
scripts/build-cube-images.sh \
  --registry ghcr.io/shekohex \
  --hakim-tag <immutable-hakim-tag>

# Build + push a specific immutable tag (refuses to overwrite an existing tag).
scripts/build-cube-images.sh \
  --registry bbcr.0iq.xyz/hakim \
  --variants js \
  --tag cube-hakim-js-<hakim-commit>-<utc-stamp> \
  --hakim-tag <immutable-hakim-tag> \
  --push
```

The pipeline script can also build cube images alongside the normal ones. Cube
images receive only the immutable `RUN_REF` tag; it never adds or publishes a
`cube-hakim-*:latest` tag:

```bash
./scripts/build.sh --cube-variants js
./scripts/build.sh --cube-variants all
```

Never reuse or move a published cube tag: Cube template artifacts reference the
resolved digest, so an overwritten tag silently changes what a new template
builds from. `CUBE_ALLOW_TAG_OVERWRITE=true` exists only for local retries.

Record per release:

- source Hakim commit and `hakim-<variant>` tag
- cube base tag + digest and envd ref (`/etc/cubesandbox-envd-ref`)
- `cube-hakim-<variant>` immutable tag and pushed digest
  (`docker buildx imagetools inspect <ref>`)

## Baked tool contract

The base and tooling layers already ship the shared primitives, so the cube
layer only adds what the review below identified as missing.

1. **Always baked primitives** — Git, GitHub CLI, OpenSSH client, ripgrep, fd,
   jq, yq, curl, wget, ca-certificates, tar, unzip, rsync, zip,
   build-essential, pkg-config, shellcheck, Docker CLI + Compose + Buildx,
   Chrome + chromedriver, Xvfb/xauth/x11-utils, `libvulkan1`,
   `mesa-vulkan-drivers`, mise.
2. **Language-image tools** — Node/Bun/npm/pnpm and Python/uv come from
   `hakim-tooling`; each `hakim-<variant>` adds its compiler/debugger stack
   (dotnet, rust, php/laravel, elixir/phoenix, java/android).
3. **Agent CLIs** — no agent CLI is baked by the cube adapter. Project-specific
   images should add only the agents they need. T3's existing installer registers
   a systemd service, so it needs a Cube-compatible project-image installation
   path rather than the Coder module unchanged.
4. **Runtime-injected secrets/config** — provider tokens, `~/.gitconfig`, SSH
   keys, OpenCode `auth.json`/config and repository data are injected when a
   sandbox is created or initialized, never baked.
5. **Services requiring explicit startup** — Nix, D-Bus, the desktop stack, the
   Coder agent and T3 are deliberately not started by the cube entrypoint.
   Docker and Xvfb are the only services the entrypoint owns.

## Validation

Docker-level contract (run wherever a privileged Docker daemon is available):

```bash
scripts/smoke-test-cube-image.sh --image ghcr.io/shekohex/cube-hakim-js:<tag>
```

It asserts: PID 1 is tini, `:49983/health` returns 204, envd/cube-entrypoint
files exist, Vulkan packages installed, toolchains resolve in a **non-login**
`coder` shell, `docker info` works as root and `coder`, `coder` runs a real
nested container, Xvfb answers on `:99`, a headed Chrome session attached to
`:99` executes JavaScript through a local page, and `SIGTERM` stops
cube-entrypoint, dockerd and Xvfb in order with a clean exit code.

Cube-level contract (run on the Cube Node, see the `cubesandbox-pve` repo):
template creation, E2B command/file/PTY APIs as `root` and `coder`, then ten
create/run/destroy cycles ending with zero sandboxes, no Cube shims, no
non-ready TAPs and no blocked KVM tasks.

## Creating a Cube template

```bash
cubemastercli tpl create-from-image \
  --image bbcr.0iq.xyz/hakim/cube-hakim-js:<immutable-tag> \
  --alias hakim-js \
  --writable-layer-size 20G \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health
```

Keep the pilot alias until the new template passes the Cube-level contract, then
promote the alias.

## Decisions and risks

- **Ordered readiness instead of a custom health port.** `envd` starting after
  Docker and Xvfb means the standard `:49983/health` probe is sufficient; no
  extra readiness server or `--expose-port` is required.
- **Storage driver fallback.** `overlay2` is preferred; the microVM kernel may
  not expose overlayfs or `/dev/fuse`, so `fuse-overlayfs` and `vfs` are tried
  explicitly and the chosen driver is logged.
- **Snapshot capture.** Cube freezes the running microVM after the probe passes,
  so Docker and Xvfb state is part of the template snapshot. Drivers must be
  able to resume from that state; validate after the first restore as well as
  after fresh boot.
- **Nested container image pull.** The smoke nested-container check builds a
  `scratch` image locally so it needs no registry egress; real workloads that
  pull images need sandbox egress (CubeEgress).
