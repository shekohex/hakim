# Hakim: Universal Coder Templates

Hakim provides Coder templates and prebuilt DevContainer images for AI-assisted development across multiple language stacks.

## DevContainer Images

Images follow the DevContainer Features model and are also OCI-ready for Proxmox LXC usage. The base image can run `coder agent` directly through `CODER_AGENT_URL` and `CODER_AGENT_TOKEN`.

| Image | Variant | Key tooling | Description |
| :--- | :--- | :--- | :--- |
| `hakim-base` | Base | `mise`, common utils | Minimal Debian Trixie image with Docker client and core tooling. |
| `hakim-php` | PHP | `php:8.4`, `laravel`, `nodejs`, `bun` | Laravel-focused workspace with PHP and JS runtimes. |
| `hakim-dotnet` | .NET | `dotnet:10`, `dotnet:latest`, `nodejs`, `bun` | .NET SDKs with JS runtimes. |
| `hakim-rust` | Rust | `rust:stable`, `nodejs`, `bun` | Rust toolchain with JS runtimes. |
| `hakim-js` | JS | `nodejs:lts`, `bun:latest` | JavaScript workspace with Node.js LTS and Bun. |
| `hakim-elixir` | Elixir | `elixir`, `phoenix`, `postgresql-tools`, `nodejs`, `bun` | Elixir/Phoenix workspace with PostgreSQL client tools and JS runtimes. |

## Templates

- Docker template: `coder/templates/hakim`
- Proxmox template: `coder/templates/hakim-proxmox`
- GitHub Actions template: `coder/templates/hakim-github-actions`

For Proxmox, templates are pre-pulled into `vztmpl` storage. With `enable_home_disk = true`, `/home/coder` is persisted and Docker data is stored at `/home/coder/.local/share/docker` to survive container rebuilds.

The GitHub Actions template runs the published Hakim GHCR images on GitHub-hosted runners, keeps the workspace step under 350 minutes, and stores encrypted `/home/coder` snapshots as Actions artifacts for restartable one-off workspaces.

The Coder control plane for that template should run on the custom `hakim-coder` image, which extends the official Coder image with provisioner-side tools such as `jq` and `age` and bundles the custom Hakim Terraform provider used to manage GitHub Actions runs. Its Terraform CLI config is stored outside `/home/coder` so persistent home mounts do not hide the provider mirror.

## Common Template Parameters

| Parameter | Description | Default |
| :--- | :--- | :--- |
| `image_variant` | Workspace image variant | `base` |
| `git_url` | Repository to clone on startup | `""` |
| `git_branch` | Branch to clone and validate for yield flow | `"main"` |
| `opencode_auth` | OpenCode auth JSON | `{}` |
| `opencode_config` | OpenCode config JSON | `{}` |
| `default_env` / `secret_env` | Environment variable injection | `{}` |
| `preview_port` | Preview app port | `3000` |
| `setup_script` | Startup shell script | `""` |
| `persist_paths` | Encrypted snapshot allowlist under `/home/coder` | common config/state paths |
| `persist_excludes` | Gitignore-style exclusions for `persist_paths` | generated config files |
| `cache_paths` | Reproducible home paths restored through GitHub cache | editor/runtime caches |
| `enable_et` | Enable ET-based resilient SSH transport | `true` |
| `enable_proliferate` | Expose the Proliferate runtime gateway alongside the OpenCode app | `false` |
| `proliferate_release_ref` | Proliferate runtime release tag | `coder-module-v0.1.0` |
| `proliferate_gateway_url` | Optional Proliferate gateway URL | `""` |

## GitHub Actions Template Setup

When `enable_proliferate = true`, the template imports the released Proliferate Coder module from the GitHub release tarball and exposes its Caddy-fronted app on port `20000` while keeping the standalone OpenCode app available on `4096`.

- Install local tooling with `mise install` so `age` and `terraform` are available.
- Generate the snapshot encryption key with `secret_key="$(mise exec -- age-keygen)"`.
- Derive the public key with `public_key="$(printf '%s\n' "$secret_key" | mise exec -- age-keygen -y /dev/stdin)"`.
- Store the private key in the control repo secret `HAKIM_WORKSPACE_AGE_SECRET_KEY`.
- Set template `secret_env` to include `GITHUB_API_TOKEN`; the template uses it both for provider-side Actions dispatch/stop and for `GH_TOKEN` inside the workspace container.
- Paste `public_key` into the template parameter `actions_age_public_key`.
- Reusable control-plane action lives in `.github/actions/hakim-workspace` and the local wrapper workflow lives in `.github/workflows/hakim-workspace.yml`.
- Build the control-plane image locally with `scripts/build-coder-image.sh`, which reads `CODER_VERSION` from the environment or `.env` and tags `hakim-coder:<CODER_VERSION>`.
- Build the local provider binary with `scripts/build-terraform-provider-hakim.sh` when you need a dev override outside the custom Coder image.

## Resilient SSH (Optional ET Mode)

`enable_et` is enabled by default. Workspace side services run on loopback only:

- `etserver` on `127.0.0.1:2022`
- `sshd` on `127.0.0.1:2244`

```mermaid
flowchart LR
  A[ssh <workspace>.coder] --> B[ProxyCommand helper]
  B --> C[coder port-forward]
  B --> D[local et client]
  C --> E[workspace etserver 127.0.0.1:2022]
  D --> E
  D --> F[workspace sshd 127.0.0.1:2244]
```

Set ProxyCommand on developer machine:

```sshconfig
Host coder.* *.coder
  User coder
  IdentitiesOnly yes
  IdentityFile ~/.ssh/coder-keys/%h/id_ed25519
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/coder_known_hosts
  ProxyCommand ~/.ssh/scripts/coder-et-proxy.sh %h %p %r
```

Local prerequisites:

- `coder` CLI
- `et`
- `nc`

Install example (macOS/Homebrew):

```bash
brew install coder/coder/coder MisterTea/et/et netcat
```

References:

- ET website: https://mistertea.github.io/EternalTerminal/
- ET docs/install: https://github.com/MisterTea/EternalTerminal
- Coder docs: https://coder.com/docs
- ET module details and FAQ: `coder/modules/et/README.md`

## Local OpenCode Attach Helper

Install on your developer machine:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/shekohex/hakim/main/scripts/oca.sh -o ~/.local/bin/oca
chmod 0755 ~/.local/bin/oca
```

Local prerequisites:

- `coder` CLI
- `opencode`
- `curl`

Examples:

```bash
oca list
oca list --verbose
oca doctor
oca doctor my-workspace
oca status my-workspace
oca --verbose my-workspace
oca my-workspace
oca my-workspace --dir api
oca my-workspace --dir ~/project/foo --tcp 3000:3000
oca my-workspace --dir services/api run "fix the failing tests"
```

Commands:

- `oca list` proxies to `coder list`
- `oca doctor [workspace]` checks local tooling, Coder auth, and optional workspace/OpenCode reachability
- `oca status <workspace>` shows `coder show` output plus OpenCode health

`--dir` maps to remote workspace paths: absolute paths stay absolute, `~/...` expands to `/home/coder/...`, and relative paths resolve from `/home/coder/project`.
`--tcp` uses the same syntax and local:remote ordering as `coder port-forward --tcp`.
`--verbose` prints wrapper steps and keeps temp logs/state for debugging.

## Build

Prerequisites:

- Docker
- `@devcontainers/cli`

Build all images:

```sh
./scripts/build.sh
```

## Extending Hakim

Add a feature:

1. Create `devcontainers/.devcontainer/features/src/<feature-name>`
2. Add `devcontainer-feature.json` and `install.sh`
3. Optionally wrap upstream features via `features` in `devcontainer-feature.json`

Add a new image variant:

1. Create `devcontainers/.devcontainer/images/<variant>/.devcontainer/devcontainer.json`
2. Base it on `ghcr.io/shekohex/hakim-base:latest`
3. Reference feature paths from `../../../features/src/<feature>`

## License

MIT
