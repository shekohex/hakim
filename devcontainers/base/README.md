# Hakim Base Image

## Summary

This is the foundational image for the Hakim Coder Template system. It is based on `debian:bookworm-slim` and includes:

- **Docker-in-Docker**: Pre-configured for running containers inside the workspace.
- **Mise**: A polyglot tool version manager, installed globally at `/usr/local/bin/mise`.
- **Common Tools**: `curl`, `wget`, `git`, `jq`, `unzip`, `sudo`.
- **Coder User**: A non-root user `coder` with passwordless sudo.

## Usage

This image is intended to be used as a base for other variants (PHP, .NET, etc.) using the DevContainer CLI.

```json
"image": "ghcr.io/shekohex/hakim-base:latest"
```

## Build

Use the `scripts/build.sh` script in the root of the repository to build this image and its variants.

### Building Manually

The `scripts/build.sh` script now automatically detects your `GITHUB_TOKEN` from the environment or the `gh` CLI to prevent rate limits.

If you prefer to build manually with `docker`:

```bash
export GITHUB_TOKEN=$(gh auth token) # or your PAT
docker build \
  --secret id=github_token,env=GITHUB_TOKEN \
  -f devcontainers/base/Dockerfile .
```

