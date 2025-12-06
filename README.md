# Hakim: Universal Coder Templates

Universal Coder templates with prebuilt DevContainer images and OpenCode AI integration.

## What's inside
- **DevContainers**: Base Debian image with Docker client and [Mise](https://mise.jdx.dev/) for tool management.
- **Variants**:
  - **Base**: Minimal image with essential tools.
  - **PHP**: Laravel with PHP 8.4.
  - **.NET**: .NET 10.0 (Template option available).
- **Template**: `coder-templates/hakim` with OpenCode, code-server, Windsurf, optional Vault integration, and more.
- **Build tooling**: `scripts/build.sh` builds base and all variants using `devcontainer build`.

## Usage
1. Push the `coder-templates/hakim` template to your Coder deployment.
2. Create a workspace and configure the parameters:
   - **Environment**: Select from Base, Laravel (PHP 8.4), .NET 10.0, or Custom.
   - **Image URL (Custom)**: Specify a custom image URL if "Custom" environment is selected.
   - **Git Repository URL**: Auto-clone a repository on startup.
   - **OpenCode Auth/Config**: Configuration for OpenCode AI.
   - **System Prompt**: Custom instructions for the AI agent.
   - **Environment Variables**: Inject `user_env` (JSON) and `secret_env` (Masked JSON).
   - **Enable Vault CLI**: Install and authenticate Vault via GitHub token.
3. OpenCode tasks are wired via `coder_ai_task`.

## Build images
Prerequisites: Docker, DevContainer CLI (`bun install -g @devcontainers/cli` or `npm`).

```sh
./scripts/build.sh
```
Tags: `ghcr.io/shekohex/hakim-<variant>:latest`.

## Add a new variant
1. Create `devcontainers/variants/<name>/.devcontainer/devcontainer.json` that references `ghcr.io/shekohex/hakim-base:latest` and adds features.
2. Re-run `./scripts/build.sh` to produce `hakim-<name>` image.

## License
MIT
