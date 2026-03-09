---
display_name: Hakim GitHub Actions
description: GitHub Actions-backed Hakim workspace with encrypted home snapshots
icon: https://cdn.simpleicons.org/githubactions?viewbox=auto
verified: true
tags: [github-actions, ai, ephemeral]
---

# Hakim GitHub Actions Template

Run Hakim workspaces inside GitHub Actions using the published GHCR images.

## What you get

- Existing Hakim images (`ghcr.io/shekohex/hakim-<variant>:latest`)
- OpenCode, OpenChamber, code-server, tmux, Zed, ET, and the existing Git helpers
- Encrypted allowlisted home snapshots restored from GitHub Actions artifacts
- Reproducible cache paths restored through GitHub cache
- `GH_TOKEN` injected from `secret_env.GITHUB_API_TOKEN` inside the workspace container

## Required setup

1. Run the Coder control plane with the custom `hakim-coder` image so provisioner-side tools like `jq` and `age` are available. The image keeps Terraform CLI config outside `/home/coder`, which is important when the home directory is mounted persistently.
2. Add a tiny wrapper workflow that calls `shekohex/hakim/.github/actions/hakim-workspace@main`.
3. Create the repository secret `HAKIM_WORKSPACE_AGE_SECRET_KEY` with an age secret key.
4. Set `secret_env` to include `GITHUB_API_TOKEN`, for example `{"GITHUB_API_TOKEN":"ghp_xxx"}`, so the custom Hakim Terraform provider can dispatch and cancel workflow runs.
5. Paste the matching age public key into the template parameter `actions_age_public_key`.

```yaml
name: Hakim Workspace

on:
  workflow_dispatch:
    inputs:
      workspace_id:
        required: true
        type: string
      workspace_name:
        required: true
        type: string
      manifest:
        required: true
        type: string

jobs:
  workspace:
    runs-on: ubuntu-latest
    timeout-minutes: 360
    permissions:
      actions: write
      contents: read
      packages: read
    steps:
      - uses: shekohex/hakim/.github/actions/hakim-workspace@main
        with:
          workspace_id: ${{ inputs.workspace_id }}
          workspace_name: ${{ inputs.workspace_name }}
          manifest: ${{ inputs.manifest }}
          age_secret_key: ${{ secrets.HAKIM_WORKSPACE_AGE_SECRET_KEY }}
          control_gh_token: ${{ github.token }}
```

## Generate the age key

- Install tooling locally with `mise install`.
- Generate a new keypair with `secret_key="$(mise exec -- age-keygen)"`.
- Derive the public key with `public_key="$(printf '%s\n' "$secret_key" | mise exec -- age-keygen -y /dev/stdin)"`.
- Store the private key in the repository secret `HAKIM_WORKSPACE_AGE_SECRET_KEY` and paste `public_key` into the template parameter `actions_age_public_key`.
- Example secret setup:

```bash
secret_key="$(mise exec -- age-keygen)"
public_key="$(printf '%s\n' "$secret_key" | mise exec -- age-keygen -y /dev/stdin)"
printf '%s\n' "$secret_key" | gh secret set HAKIM_WORKSPACE_AGE_SECRET_KEY
printf '%s\n' "$public_key"
```

## Persistence model

- `persist_paths` controls which home-relative paths are encrypted and restored.
- `persist_excludes` applies gitignore-style filters to those persisted paths.
- `cache_paths` controls reproducible directories restored through GitHub cache.
- Git work should live in the cloned repository and be pushed upstream before stopping the workspace.

## Security model

- Workflow dispatch input contains only encrypted workspace bootstrap data.
- The custom Hakim Terraform provider stores the exact GitHub Actions `run_id` in Terraform state, then uses it for deterministic stop/cancel operations.
- The provider and the workspace container both read `GITHUB_API_TOKEN` from `secret_env`.
- The control workflow uses the built-in `GITHUB_TOKEN` for Actions lifecycle and artifacts.
- The workspace container receives `GH_TOKEN` from the encrypted manifest, not from `github.token`.
- Do not enable verbose shell tracing in the control workflow if you are handling private work.

## Single-tenant note

This template currently assumes a single trusted operator. The control repo still uses the fixed age secret name `HAKIM_WORKSPACE_AGE_SECRET_KEY` in v1.
