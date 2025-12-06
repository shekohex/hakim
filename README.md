# Hakim: Universal Coder Templates

Universal Coder templates with prebuilt DevContainer images and OpenCode AI integration.

## Whats inside
- **DevContainers**: Base Debian image with Docker client and Mise; PHP variant; easy to add more.
- **Template**: `coder-templates/hakim` with OpenCode, code-server, Windsurf, Cursor, JetBrains, git-clone, dotfiles, preview app, stats metadata.
- **Build tooling**: `scripts/build.sh` builds base and all variants with `devcontainer build`.
- **Design plan**: `docs/plans/2025-12-06-hakim-template-design.md`.

## Build images
Prereqs: Docker, DevContainer CLI.
```sh
./scripts/build.sh
```
Tags: `ghcr.io/shekohex/hakim-<variant>:latest`.

## Use the Coder template
1. Push the `coder-templates/hakim` template to your Coder deployment.
2. Create a workspace, choose an image variant (Base, PHP, DotNet), optional git URL, and paste your `opencode` auth JSON.
3. OpenCode tasks are wired via `coder_ai_task`.

## Add a new variant
1. Create `devcontainers/variants/<name>/.devcontainer/devcontainer.json` that references `ghcr.io/shekohex/hakim-base:latest` and adds features.
2. Re-run `./scripts/build.sh` to produce `hakim-<name>` image.

## License
MIT
