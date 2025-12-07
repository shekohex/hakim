# Hakim Project Knowledge Base

## Overview
Hakim is an Infrastructure-as-Code (IaC) project providing universal Coder templates and composable DevContainer images.
- **Templates**: Terraform-based workspace definitions with OpenCode integration.
- **Images**: Docker-based DevContainers built with composable features.

## Architecture

### Directory Structure
- `coder-templates/hakim/`: Main Coder template (`main.tf`, `bootstrap.sh`).
- `devcontainers/`:
  - `base/`: Base Debian image (`Dockerfile`).
  - `.devcontainer/`:
    - `features/src/`: Local DevContainer features (e.g., `nodejs`, `dotnet`, `rust`).
    - `images/<variant>/.devcontainer/`: Image definitions (`devcontainer.json`).
- `scripts/`: Build tooling (`build.sh`).

### Key Technologies
- **Docker**: Base image and variants.
- **DevContainer CLI**: Builds features and images.
- **Mise**: Manages tool versions (Node.js, Bun) in features.
- **Terraform**: Defines Coder workspaces.

## Workflows

### 1. Build Images
Run the build script to build the base image and all variants (`php`, `dotnet`, `rust`, `js`).
```bash
./scripts/build.sh
```
*Note: Requires Docker and `@devcontainers/cli`.*

### 2. Add New Feature
1. Create directory: `devcontainers/.devcontainer/features/src/<feature-name>`
2. Add `devcontainer-feature.json` (metadata) and `install.sh` (logic).
3. **Pattern**: Prefer wrapping upstream features (using `features` property) or using `mise` for tool installation over raw install scripts.

### 3. Add New Image Variant
1. Create `devcontainers/.devcontainer/images/<variant-name>/.devcontainer/devcontainer.json`.
2. Inherit from base: `"image": "ghcr.io/shekohex/hakim-base:latest"`.
3. Add features relative to src: `"../../../features/src/<feature>": { ... }`.
4. Run `./scripts/build.sh` to compile.

### 4. Update Coder Template
1. Edit `coder-templates/hakim/main.tf`.
2. Add option to `image_variant` parameter.
3. Add `coder_workspace_preset` for quick start.
4. Validate: `terraform fmt -recursive && terraform validate`.

## Style Guide
- **Terraform**: Use snake_case. Run `terraform fmt`.
- **Shell**: Use `#!/bin/bash` with `set -e`. Prefer `mise` for installs.
- **Commits**: Conventional Commits (`feat`, `fix`, `docs`, `chore`).

## Troubleshooting
- **Build Fails**: Check `scripts/build.sh` logic. Ensure correct relative paths in `devcontainer.json`.
- **Unbound Vars**: `scripts/build.sh` uses `set -u`. Ensure CI variables like `GITHUB_ACTIONS` have defaults (`${VAR:-default}`).
