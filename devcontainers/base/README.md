# Hakim Base Image

## Summary

This is the foundational image for the Hakim Coder Template system. It is based on `debian:trixie-slim` and includes:

- **Docker-in-Docker**: Pre-configured for running containers inside the workspace.
- **Mise**: A polyglot tool version manager, installed globally at `/usr/local/bin/mise`.
- **Common Tools**: `curl`, `wget`, `git`, `jq`, `unzip`, `sudo`.
- **Resilient SSH Tooling**: `et` (EternalTerminal) and `openssh-server` are available for optional ET-based transport.
- **Browser Testing**: Chrome for Testing and matching ChromeDriver are installed for automation.
- **Headless Desktop Runtime**: Xvfb, AppImage FUSE support, Electron runtime libraries, software GL defaults, image/PDF/media tools, and common fonts.
- **Coder User**: A non-root user `coder` with passwordless sudo.
- **Coder-Agent-Native Entrypoint**: `/usr/local/bin/hakim-entrypoint` prepares `coder` home/project dirs and starts `coder agent` automatically when `CODER_AGENT_URL` and `CODER_AGENT_TOKEN` are set.

## Browser Tooling Paths

- Chrome launcher: `/usr/bin/google-chrome-stable` (symlink to `/opt/chrome-linux64/chrome`)
- Chrome binary: `/opt/chrome-linux64/chrome`
- ChromeDriver launcher: `/usr/local/bin/chromedriver` (symlink to `/opt/chromedriver-linux64/chromedriver`)
- ChromeDriver binary: `/opt/chromedriver-linux64/chromedriver`
- Version source: Chrome for Testing stable channel (`GOOGLE_CHROME_VERSION` build arg)

## Headless Runtime

- Default virtual display: `DISPLAY=:99`
- Default Xvfb screen: `1280x1024x24`
- Software GL: `LIBGL_ALWAYS_SOFTWARE=1`
- Non-systemd containers start Xvfb from `/usr/local/bin/hakim-entrypoint` when `START_XVFB` is unset, `1`, or `true`.
- Systemd containers enable `hakim-xvfb.service` by default.
- Override the screen size with `XVFB_SCREEN`, e.g. `XVFB_SCREEN=1920x1080x24`.
- Disable entrypoint-managed Xvfb with `START_XVFB=0` when another display server is provided.
- Override systemd Xvfb settings with `/etc/hakim/xvfb.env`.

The base image includes core runtime tools needed by headless Electron/AppImage/browser workflows: `libfuse2`, `xvfb`, `xauth`, `x11-utils`, `xdotool`, `scrot`, `xclip`, `wmctrl`, `ffmpeg`, `imagemagick`, `webp`, `librsvg2-bin`, `poppler-utils`, `qpdf`, `ghostscript`, `file`, common desktop MIME utilities, and Noto fonts.

## Shell Defaults

- `PAGER=less`
- `LESS=-R`
- `EDITOR=nvim` when `nvim` is installed
- `VISUAL=nvim` when `nvim` is installed
- `alias vim=nvim` when `nvim` is installed

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

## Smoke Tests

CI runs `scripts/smoke-test-image.sh` after each image build. To run locally, set `CI=true` so the script does not skip checks:

```bash
CI=true scripts/smoke-test-image.sh --target base --image ghcr.io/shekohex/hakim-base:latest
CI=true scripts/smoke-test-image.sh --target tooling --image ghcr.io/shekohex/hakim-tooling:latest
```

The base smoke test checks core binaries, browser tooling, profile defaults, and a real Xvfb display startup. Tooling smoke tests check language tooling and globally exposed mise tools.
