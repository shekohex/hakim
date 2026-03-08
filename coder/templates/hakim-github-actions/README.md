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
- Encrypted `/home/coder` snapshots restored from GitHub Actions artifacts
- `~/.ageignore` support for excluding transient files from snapshots
- `GH_TOKEN` injected from a repository secret inside the workspace container

## Required setup

1. Add `.github/workflows/hakim-workspace.yml` and `.github/scripts/hakim-workspace.sh` to the control repository.
2. Create the repository secret `HAKIM_WORKSPACE_AGE_SECRET_KEY` with an age secret key.
3. Create the repository secret `HAKIM_WORKSPACE_GH_TOKEN` with a GitHub token for `gh` and private repository access inside the workspace.
4. Configure Coder external auth for GitHub with access to dispatch workflows and manage Actions variables for the control repository.
5. Paste the matching age public key into the template parameter `actions_age_public_key`.

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
gh auth token | gh secret set HAKIM_WORKSPACE_GH_TOKEN
printf '%s\n' "$public_key"
```

## Snapshot filtering

- The template seeds `/home/coder/.ageignore` from the `snapshot_ageignore` parameter when the file is missing.
- The default rules skip common transient paths such as `node_modules`, Python caches, `target`, `dist`, `build`, and `.gradle` under `/home/coder/project`.
- Edit `/home/coder/.ageignore` inside the workspace to customize future snapshots.

## Security model

- Workflow dispatch input contains only encrypted workspace bootstrap data.
- The control workflow uses the built-in `GITHUB_TOKEN` for Actions lifecycle and artifacts.
- The workspace container receives `GH_TOKEN` from the configured repository secret, not from `github.token`.
- Do not enable verbose shell tracing in the control workflow if you are handling private work.

## Single-tenant note

This template currently assumes a single trusted operator. The fixed secret names are intentional for v1.
