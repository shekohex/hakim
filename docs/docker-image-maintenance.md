# Docker Image Maintenance

## Goals

- Keep rebuilds reproducible and cache-friendly.
- Make small version bumps change only a few layers.
- Control update cadence (every 4–6 weeks) without surprise drift.

## Image Flow (What Updates Propagate Where)

- `hakim-base` is the foundation image built from `devcontainers/base/Dockerfile`.
- Variant images (`hakim-js`, `hakim-php`, `hakim-elixir`, etc.) are built from the base image.
- Updating a tool in the base image (like OpenCode) only updates the base image.
- Variants will NOT automatically receive base changes until they are rebuilt and pushed.
- Users pulling `hakim-base:latest` get the new OpenCode version after base rebuild.
- Users pulling `hakim-<variant>:latest` get the new OpenCode version only after variant rebuild.

## Update Cadence (Recommended)

- Base OS + apt snapshot: every 4–6 weeks.
- Chrome / Docker CLI / toolchain: only as needed.
- OpenCode: batch updates (daily releases can be too churny); pick a cadence.

## Base Image Updates

### 1) Update Debian base digest

File: `devcontainers/base/Dockerfile`

- Update `DEBIAN_IMAGE` with the latest digest:

```bash
docker buildx imagetools inspect debian:bookworm-slim
```

Pick the `linux/amd64` manifest digest and set:

```
ARG DEBIAN_IMAGE=debian:bookworm-slim@sha256:<digest>
```

### 2) Update Debian apt snapshot (reproducible apt)

File: `devcontainers/base/Dockerfile`

- Update the snapshot timestamp:

```
ARG DEBIAN_SNAPSHOT=YYYY-MM-DDT000000Z
```

Use a single date and keep the same for `debian`, `debian-updates`, and `debian-security`.

### 3) Update Docker CLI source image (if needed)

File: `devcontainers/base/Dockerfile`

```bash
docker buildx imagetools inspect docker:28.3.3-cli
```

Set:

```
ARG DOCKER_CLI_IMAGE=docker:28.3.3-cli@sha256:<digest>
```

### 4) Update Mise version (if needed)

Files:
- `devcontainers/base/Dockerfile`
- `devcontainers/base/install-mise.sh`

Steps:

```bash
gh api repos/jdx/mise/releases/latest -q '.tag_name'
curl -fsSL https://github.com/jdx/mise/releases/download/<tag>/SHASUMS256.txt | rg 'linux-(x64|arm64)\.tar\.gz'
```

Update:

```
ARG MISE_VERSION=<version>
ARG MISE_SHA256_X64=<sha256>
ARG MISE_SHA256_ARM64=<sha256>
```

### 5) Update base tool versions (if needed)

File: `devcontainers/base/Dockerfile`

- Update the version args in the downloader stages:
  - `CODER_VERSION`
  - `CODE_SERVER_VERSION`
  - `OPENCODE_VERSION`
  - `GOOGLE_CHROME_VERSION`

Only the specific tool layer should change when these are bumped.

## Variant Feature Updates

Defaults are now pinned. If you want to update a tool used by a feature, update both the feature default and any variant configs that override it.

Examples:

- Node.js default: `devcontainers/.devcontainer/features/src/nodejs/devcontainer-feature.json`
- Bun default: `devcontainers/.devcontainer/features/src/bun/devcontainer-feature.json`
- Uv + Python: `devcontainers/.devcontainer/features/src/uv/devcontainer-feature.json`
- OpenChamber: `devcontainers/.devcontainer/features/src/openchamber/devcontainer-feature.json`
- OpenClaw: `devcontainers/.devcontainer/features/src/openclaw/devcontainer-feature.json`
- Phoenix: `devcontainers/.devcontainer/features/src/phoenix/devcontainer-feature.json`
- PostgreSQL tools: `devcontainers/.devcontainer/features/src/postgresql-tools/devcontainer-feature.json`
- Rust: `devcontainers/.devcontainer/features/src/rust/devcontainer-feature.json`
- Dotnet: `devcontainers/.devcontainer/features/src/dotnet/devcontainer-feature.json`
- Laravel: `devcontainers/.devcontainer/features/laravel/devcontainer-feature.json`

Then update any variant configs that pin versions:

- `devcontainers/.devcontainer/images/js/.devcontainer/devcontainer.json`
- `devcontainers/.devcontainer/images/php/.devcontainer/devcontainer.json`
- `devcontainers/.devcontainer/images/dotnet/.devcontainer/devcontainer.json`
- `devcontainers/.devcontainer/images/rust/.devcontainer/devcontainer.json`
- `devcontainers/.devcontainer/images/elixir/.devcontainer/devcontainer.json`

## How to Roll an OpenCode Update

1) Update `OPENCODE_VERSION` in `devcontainers/base/Dockerfile`.
2) Rebuild and push the base image.
3) Rebuild and push all variants to propagate the new base.

If you only rebuild base, the variants will still point to the old base layers.

## Build and Publish

Local:

```bash
./scripts/build.sh
```

CI:
- `.github/workflows/ci.yml` builds base and variants.
- Any changes in `devcontainers/**` currently trigger full rebuilds.

## Verify Cache/Layer Reuse (No Pulls)

Compare layer overlap between two base tags:

```bash
A=ghcr.io/shekohex/hakim-base:latest@sha256:<amd64_digest>
B=ghcr.io/shekohex/hakim-base:<old_tag>@sha256:<amd64_digest>
comm -12 \
  <(docker buildx imagetools inspect --raw $A | jq -r '.layers[].digest' | sort) \
  <(docker buildx imagetools inspect --raw $B | jq -r '.layers[].digest' | sort) \
| wc -l
```

Expected after pinning: most layers shared; only 1–2 layers should change for small bumps.

## Troubleshooting

- If every layer changes on a small bump:
  - Confirm `DEBIAN_IMAGE`, `DEBIAN_SNAPSHOT`, and `DOCKER_CLI_IMAGE` are pinned.
  - Confirm `install-mise.sh` uses the pinned release (not `mise.run`).
  - Confirm feature defaults are not pulling `latest`.
