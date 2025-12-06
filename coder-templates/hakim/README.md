# Hakim Universal Template

This template uses pre-built DevContainer images to provide a robust development environment.

## Features

- **Base Image**: Debian-based with `mise`, `docker`, and common tools.
- **Variants**: Select PHP, .NET, or Base at creation.
- **AI Integration**: OpenCode agent pre-installed.
- **Persistence**: `/home/coder` is persistent.

## How to Use

1. Select "Hakim Universal" template.
2. Choose your environment (Base, PHP, etc.).
3. (Optional) Provide a Git URL to clone.
4. (Optional) Paste your `opencode_auth.json` for AI features.

## Building Images

Run `scripts/build.sh` locally to rebuild the base and variant images.
