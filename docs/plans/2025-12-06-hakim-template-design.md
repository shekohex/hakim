# Hakim Universal AI Coder Template Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a "Universal" Coder template system that pre-builds Docker images (via DevContainers) with AI agents and tools, and lets users select their variant (PHP, .NET) at workspace creation.

**Architecture:**
1.  **Image System:** Base image with global tools (Mise) + Variant images (PHP, .NET) built via `devcontainer-cli`.
2.  **Template:** Terraform template using Coder Modules (OpenCode, Git) and dynamic parameters to inject the right image and config.

**Tech Stack:** Docker, DevContainers, Terraform, Mise, Bash.

---

### Phase 1: Base Image & Tooling

**Task 1.1: Create Base Image Definition**

**Files:**
- Create: `devcontainers/base/Dockerfile`
- Create: `devcontainers/base/install-mise.sh`
- Create: `devcontainers/base/devcontainer.json`

**Step 1: Create install-mise.sh**

Create `devcontainers/base/install-mise.sh`:
```bash
#!/bin/bash
set -e
# Install mise to /usr/local/bin/mise
curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# Create global config dir
mkdir -p /etc/mise
echo 'experimental = true' > /etc/mise/config.toml

# Setup profile script for all users
cat << 'EO_PROFILE' > /etc/profile.d/mise.sh
export MISE_INSTALL_PATH=/usr/local/bin/mise
eval "$(/usr/local/bin/mise activate bash)"
EO_PROFILE
chmod +x /etc/profile.d/mise.sh
```

**Step 2: Create Dockerfile**

Create `devcontainers/base/Dockerfile`:
```dockerfile
FROM debian:bookworm-slim

# Install common dependencies
RUN apt-get update && apt-get install -y \
    curl wget git jq unzip sudo \
    ca-certificates gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker (client only, host docker socket will be mounted)
COPY --from=docker:dind /usr/local/bin/docker /usr/local/bin/

# Install Mise
COPY install-mise.sh /tmp/install-mise.sh
RUN bash /tmp/install-mise.sh && rm /tmp/install-mise.sh

# Create coder user
RUN useradd -m -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder
USER coder
```

**Step 3: Commit**
```bash
git add devcontainers/base/
git commit -m "feat(base): add initial base image definition"
```

---

### Phase 2: Build System

**Task 2.1: Create Build Script**

**Files:**
- Create: `scripts/build.sh`

**Step 1: Write Build Script**

Create `scripts/build.sh`:
```bash
#!/bin/bash
set -e

# Registry prefix
REGISTRY="ghcr.io/shekohex"
TIMESTAMP=$(date +%Y%m%d)

echo "Building Base Image..."
docker build -t "$REGISTRY/hakim-base:latest" -t "$REGISTRY/hakim-base:$TIMESTAMP" devcontainers/base

# Find variants
for variant in devcontainers/variants/*; do
    if [ -d "$variant" ]; then
        NAME=$(basename "$variant")
        echo "Building Variant: $NAME..."
        
        # Use devcontainer CLI to build
        devcontainer build \
            --workspace-folder "$variant" \
            --image-name "$REGISTRY/hakim-$NAME:latest" \
            --image-name "$REGISTRY/hakim-$NAME:$TIMESTAMP"
    fi
done

echo "Build Complete!"
```

**Step 2: Make Executable**
```bash
chmod +x scripts/build.sh
```

**Step 3: Commit**
```bash
git add scripts/build.sh
git commit -m "feat(scripts): add build automation script"
```

---

### Phase 3: Variant Definitions

**Task 3.1: Define PHP Variant**

**Files:**
- Create: `devcontainers/variants/php/.devcontainer/devcontainer.json`

**Step 1: Create devcontainer.json**

Create `devcontainers/variants/php/.devcontainer/devcontainer.json`:
```json
{
    "name": "Hakim PHP",
    "image": "ghcr.io/shekohex/hakim-base:latest",
    "features": {
        "ghcr.io/devcontainers/features/php:8": {
            "version": "8.3",
            "installComposer": true
        }
    },
    "customizations": {
        "vscode": {
            "extensions": ["DEVSENSE.phptools-vscode"]
        }
    }
}
```

**Step 2: Commit**
```bash
git add devcontainers/variants/php
git commit -m "feat(variants): add PHP variant"
```

---

### Phase 4: Coder Template

**Task 4.1: Create Main Terraform File**

**Files:**
- Create: `coder-templates/hakim/main.tf`
- Create: `coder-templates/hakim/README.md`

**Step 1: Create main.tf**

Create `coder-templates/hakim/main.tf`:
```hcl
terraform {
  required_providers {
    coder = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

provider "docker" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Parameters
data "coder_parameter" "image_variant" {
  name = "image_variant"
  display_name = "Environment"
  default = "base"
  option { name = "Base (Minimal)" value = "base" }
  option { name = "PHP 8.3" value = "php" }
  option { name = "DotNet 8" value = "dotnet" }
}

data "coder_parameter" "git_url" {
  name = "git_url"
  display_name = "Git Repository URL"
  default = ""
  description = "Optional: Auto-clone a repository"
}

data "coder_parameter" "opencode_auth" {
  name = "opencode_auth"
  display_name = "OpenCode Auth JSON"
  description = "Paste content of ~/.local/share/opencode/auth.json"
  default = "{}"
  mutable = true
}

# Resources
resource "coder_agent" "main" {
  os = "linux"
  arch = "amd64"
  startup_script = <<EOT
    #!/bin/bash
    # Ensure user mise config exists
    mkdir -p ~/.config/mise
    touch ~/.config/mise/config.toml
  EOT
}

# Modules
module "opencode" {
  source = "registry.coder.com/coder-labs/opencode/coder"
  version = "0.1.1"
  agent_id = coder_agent.main.id
  workdir = "/home/coder/project"
  auth_json = data.coder_parameter.opencode_auth.value
  report_tasks = true
}

module "git-clone" {
  count = data.coder_parameter.git_url.value != "" ? 1 : 0
  source = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url = data.coder_parameter.git_url.value
}

module "dotfiles" {
  source = "registry.coder.com/coder/dotfiles/coder"
  agent_id = coder_agent.main.id
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "ghcr.io/shekohex/hakim-${data.coder_parameter.image_variant.value}:latest"
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = "coder-${data.coder_workspace.me.id}-home"
    read_only      = false
  }
}
```

**Step 2: Commit**
```bash
git add coder-templates/hakim/
git commit -m "feat(template): add hakim universal template"
```

---
