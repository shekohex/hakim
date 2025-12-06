# Hakim Project Knowledge Base

Universal Coder templates and DevContainer images for "Hakim".

## Infrastructure Project
This is an Infrastructure-as-Code (IaC) repository, not a traditional web application.
- **Coder Templates**: Terraform-based templates in `coder-templates/`.
- **DevContainers**: Docker and DevContainer definitions in `devcontainers/`.

## Commands
- **Build All Images**: `./scripts/build.sh` (Requires Docker & DevContainer CLI).
- **Format Terraform**: `terraform fmt -recursive`
- **Install Deps**: `bun install` (for DevContainer CLI).

## Directory Structure
- `coder-templates/hakim`: Main Coder template (Terraform).
  - `main.tf`: Main infrastructure definition.
- `devcontainers/`:
  - `base/`: Base Debian image definition.
  - `variants/`: Language-specific variants (PHP, etc.).
- `scripts/`: Build and utility scripts.
- `docs/`: Documentation and design plans.

## Conventions
- **Commits**: Follow Conventional Commits (`feat`, `fix`, `chore`, etc.).
- **Tools**:
  - Use `bunx devcontainer` or installed `@devcontainers/cli`.
  - Use `terraform` for template validation.
- **Workflow**:
  - Add new variants in `devcontainers/variants/<name>`.
  - Update `coder-templates/hakim/main.tf` to expose new variants or parameters.
  - Run `./scripts/build.sh` to build and verify images locally.
