# Hakim: Universal Coder Templates

Universal Coder templates with prebuilt DevContainer images and OpenCode AI integration.

## 📦 DevContainer Images

The images are built using the [DevContainer Features](https://containers.dev/features) specification.

Hakim images are also OCI-ready for Proxmox LXC templates and can run `coder agent` directly via environment variables (`CODER_AGENT_URL`, `CODER_AGENT_TOKEN`) without SSH bootstrap.

| Image Name | Variant | Key Features | Description |
| :--- | :--- | :--- | :--- |
| `hakim-base` | Base | `mise`, `common-utils` | Minimal Debian Trixie image with Docker client and Mise. |
| `hakim-php` | PHP | `php:8.4`, `laravel`, `nodejs`, `bun` | Laravel development environment with PHP 8.4, Composer, and JS runtimes. |
| `hakim-dotnet` | .NET | `dotnet:10`, `dotnet:latest`, `nodejs`, `bun` | .NET 10 (Preview) & Latest SDKs with JS runtimes. |
| `hakim-rust` | Rust | `rust:stable`, `nodejs`, `bun` | Rust Stable toolchain with JS runtimes. |
| `hakim-js` | JS | `nodejs:lts`, `bun:latest` | Unified JavaScript environment with Node.js LTS and Bun. |
| `hakim-elixir` | Elixir | `elixir`, `phoenix`, `postgresql-tools`, `nodejs`, `bun` | Elixir + Phoenix environment with PostgreSQL client tools and JS runtimes. |

## 🛠️ Coder Template Options

The `coder-templates/hakim` template exposes several parameters to customize the workspace.

For Proxmox, use `coder/templates/hakim-proxmox` with shared pre-pulled OCI templates in Proxmox storage (`vztmpl`).
Enable `enable_home_disk` to persist `/home/coder`; Docker daemon data is then stored at `/home/coder/.local/share/docker` so pulled images survive workspace container rebuilds.

### Core Parameters
| Parameter | Description | Default | Options |
| :--- | :--- | :--- | :--- |
| **Environment** (`image_variant`) | Selects the environment image. | `base` | `base`, `php`, `dotnet`, `js`, `rust`, `elixir`, `custom` |
| **Git Repository URL** | Repository to clone on startup. | `""` | Any valid Git URL |
| **Image URL** | Custom Docker image URL (only used if Env is "Custom"). | `""` | |

### AI & Integration
| Parameter | Description | Default |
| :--- | :--- | :--- |
| **System Prompt** | Custom instructions for the OpenCode AI agent. | `""` |
| **OpenCode Auth** | JSON content of `~/.local/share/opencode/auth.json`. | `{}` |
| **OpenCode Config** | OpenCode configuration JSON. | `{}` |
| **Enable Vault CLI** | Install and authenticate Vault via GitHub token. | `false` |

### Advanced
| Parameter | Description | Default |
| :--- | :--- | :--- |
| **Environment Variables** | JSON object of env vars to inject. | `{}` |
| **Secret Env** | Masked JSON object for secrets. | `{}` |
| **Preview Port** | Web app port for the preview button. | `3000` |
| **Setup Script** | Bash script to run on startup (cloning, installs). | `""` |

## 🚀 Usage

1.  **Deploy**: Push `coder-templates/hakim` to your Coder deployment.
2.  **Create Workspace**: Select a Preset (e.g., "Laravel Quick Start", ".NET Quick Start") or configure manually.
3.  **Develop**: Connect via VS Code (Web/Desktop), SSH, or JetBrains Gateway.

## 🏗️ Build System

The project uses a custom build script that leverages the DevContainer CLI.

**Prerequisites:**
- Docker
- `@devcontainers/cli` (Install via `bun install -g @devcontainers/cli` or `npm`)

**Build Command:**
```sh
./scripts/build.sh
```
This builds the base image and all variants found in `devcontainers/.devcontainer/images/*`.

## 🧩 Adding New Components

### Add a New Feature
1. Create a folder in `devcontainers/.devcontainer/features/src/<name>`.
2. Add `devcontainer-feature.json` and `install.sh`.
3. (Optional) Wrap an upstream feature using the `features` property in `devcontainer-feature.json`.

### Add a New Image Variant
1. Create `devcontainers/.devcontainer/images/<name>/.devcontainer/devcontainer.json`.
2. Reference `ghcr.io/shekohex/hakim-base:latest`.
3. Add features pointing to `../../../features/src/<feature>`.

## License
MIT
