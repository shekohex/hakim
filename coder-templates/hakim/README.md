# Hakim Universal Template

This template uses pre-built DevContainer images to provide a robust development environment.

## Features

- **Base Image**: Debian-based with `mise`, `docker`, and common tools.
- **Variants**: Base, PHP (Laravel), .NET, or Custom Image.
- **AI Integration**: OpenCode agent pre-installed with customizable System Prompt.
- **Security**: Optional Vault integration and masked secret environment variables.
- **Persistence**: `/home/coder` is persistent.

## How to Use

1. Select "Hakim Universal" template.
2. Choose your environment (Base, PHP, .NET, or Custom).
3. (Optional) Provide a Custom Image URL if using "Custom" variant.
4. (Optional) Provide a Git URL to clone.
5. (Optional) Enable Vault and provide address/auth ID.
6. (Optional) Paste your `opencode_auth.json` and config.

## Building Images

Run `scripts/build.sh` locally to rebuild the base and variant images.
