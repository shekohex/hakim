# Hakim Base Image

## Summary

This is the foundational image for the Hakim Coder Template system. It is based on `debian:trixie-slim` and includes:

- **Docker-in-Docker**: Pre-configured for running containers inside the workspace.
- **Mise**: A polyglot tool version manager, installed globally at `/usr/local/bin/mise`.
- **Common Tools**: `curl`, `wget`, `git`, `jq`, `unzip`, `sudo`.
- **Resilient SSH Tooling**: `et` (EternalTerminal) and `openssh-server` are available for optional ET-based transport.
- **Browser Testing**: Chrome for Testing and matching ChromeDriver are installed for automation.
- **Coder User**: A non-root user `coder` with passwordless sudo.
- **Coder-Agent-Native Entrypoint**: `/usr/local/bin/hakim-entrypoint` prepares `coder` home/project dirs and starts `coder agent` automatically when `CODER_AGENT_URL` and `CODER_AGENT_TOKEN` are set.

## Browser Tooling Paths

- Chrome launcher: `/usr/bin/google-chrome-stable` (symlink to `/opt/chrome-linux64/chrome`)
- Chrome binary: `/opt/chrome-linux64/chrome`
- ChromeDriver launcher: `/usr/local/bin/chromedriver` (symlink to `/opt/chromedriver-linux64/chromedriver`)
- ChromeDriver binary: `/opt/chromedriver-linux64/chromedriver`
- Version source: Chrome for Testing stable channel (`GOOGLE_CHROME_VERSION` build arg)

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
