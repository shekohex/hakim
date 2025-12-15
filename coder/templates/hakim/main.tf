terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "docker" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# ------------------------------------------------------------------------------
# Parameters
# ------------------------------------------------------------------------------

data "coder_parameter" "image_variant" {
  name         = "image_variant"
  display_name = "Environment"
  description  = "Select the programming language environment."
  default      = "base"
  type         = "string"
  icon         = "/icon/docker.svg"
  option {
    name        = "Base (Minimal)"
    description = "Minimal image with only essential tools."
    value       = "base"
    icon        = "/icon/debian.svg"
  }
  option {
    name        = "Laravel with PHP 8.4"
    description = "Laravel with PHP 8.4 and related tools."
    value       = "php"
    icon        = "/icon/php.svg"
  }
  option {
    name        = ".NET 10.0"
    description = ".NET 10.0 with .NET SDK and related tools."
    value       = "dotnet"
    icon        = "/icon/dotnet.svg"
  }
  option {
    name        = "Node.js & Bun"
    description = "Node.js (LTS), Bun (Latest), and related tools."
    value       = "js"
    icon        = "/icon/node.svg"
  }
  option {
    name        = "Rust"
    description = "Rust (Stable) with cargo, rust-analyzer, etc."
    value       = "rust"
    icon        = "/icon/rust.svg"
  }
  option {
    name        = "Custom"
    icon        = "/emojis/1f5c3.png"
    description = "Specify a custom repo URL below"
    value       = "custom"
  }
  order = 1
}

data "coder_parameter" "image_url" {
  count        = data.coder_parameter.image_variant.value == "custom" ? 1 : 0
  name         = "image_url"
  display_name = "Image URL (Custom)"
  default      = ""
  mutable      = true
  type         = "string"
  description  = "Optional: Specify a custom image URL if you selected 'Custom' above."
  icon         = "/icon/docker.svg"
  order        = 2
}

data "coder_parameter" "git_url" {
  name         = "git_url"
  display_name = "Git Repository URL"
  default      = ""
  mutable      = true
  type         = "string"
  description  = "Optional: Auto-clone a repository on startup."
  icon         = "/icon/git.svg"
  order        = 3
}

data "coder_parameter" "opencode_auth" {
  name         = "opencode_auth"
  display_name = "OpenCode Auth JSON"
  description  = "Paste content of ~/.local/share/opencode/auth.json"
  form_type    = "textarea"
  type         = "string"
  default      = "{}"
  mutable      = true
  styling      = jsonencode({ mask_input = true })
  icon         = "/icon/opencode.svg"
  order        = 4
}

data "coder_parameter" "opencode_config" {
  name         = "opencode_config"
  display_name = "OpenCode Config JSON"
  description  = "OpenCode JSON config. https://opencode.ai/docs/config/"
  type         = "string"
  form_type    = "textarea"
  default      = "{}"
  mutable      = true
  icon         = "/icon/opencode.svg"
  order        = 5
}

data "coder_parameter" "system_prompt" {
  name         = "system_prompt"
  display_name = "System Prompt"
  type         = "string"
  form_type    = "textarea"
  description  = "System prompt for the AI agent."
  default      = ""
  mutable      = true
  icon         = "/icon/tasks.svg"
  order        = 6
}

data "coder_parameter" "user_env" {
  name         = "user_env"
  display_name = "Environment Variables (JSON)"
  description  = "JSON object of env vars to inject."
  type         = "string"
  form_type    = "textarea"
  default      = "{}"
  mutable      = true
  icon         = "/icon/terminal.svg"
  order        = 7
}

data "coder_parameter" "secret_env" {
  name         = "secret_env"
  display_name = "Secret Env (JSON)"
  description  = "Masked JSON object for secrets."
  type         = "string"
  form_type    = "textarea"
  default      = "{}"
  mutable      = true
  icon         = "https://cdn.simpleicons.org/dotenv?viewbox=auto"
  styling      = jsonencode({ mask_input = true })
  order        = 8
}

data "coder_parameter" "enable_vault" {
  name         = "enable_vault"
  display_name = "Enable Vault CLI"
  description  = "Install and auth Vault via GitHub token."
  type         = "bool"
  default      = false
  icon         = "/icon/vault.svg"
  order        = 9
}

data "coder_parameter" "vault_addr" {
  count        = data.coder_parameter.enable_vault.value ? 1 : 0
  name         = "vault_addr"
  display_name = "Vault Address"
  description  = "Vault server URL."
  type         = "string"
  default      = "http://vault:8200"
  mutable      = true
  icon         = "/icon/vault.svg"
  order        = 10
}

data "coder_parameter" "vault_github_auth_id" {
  count        = data.coder_parameter.enable_vault.value ? 1 : 0
  name         = "vault_github_auth_id"
  display_name = "Vault GitHub Auth ID"
  description  = "GitHub auth mount or role used for Vault."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/github.svg"
  order        = 11
}

data "coder_parameter" "preview_port" {
  name         = "preview_port"
  display_name = "Preview Port"
  description  = "The port the web app is running to preview in Tasks."
  type         = "number"
  default      = "3000"
  mutable      = true
  icon         = "/icon/widgets.svg"
  order        = 12
}

data "coder_parameter" "setup_script" {
  name         = "setup_script"
  display_name = "Setup Script"
  description  = "Script to run before running the agent (clone repos, start dev servers, etc)."
  type         = "string"
  form_type    = "textarea"
  default      = ""
  mutable      = false
  icon         = "/icon/terminal.svg"
  order        = 13
}

locals {
  user_env     = try(jsondecode(trimspace(data.coder_parameter.user_env.value)), {})
  secret_env   = try(jsondecode(trimspace(data.coder_parameter.secret_env.value)), {})
  combined_env = merge(local.user_env, local.secret_env)
  project_dir  = length(module.git-clone) > 0 ? module.git-clone[0].repo_dir : "/home/coder/project"
}

# ------------------------------------------------------------------------------
# Agent & AI Task
# ------------------------------------------------------------------------------

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  env            = local.combined_env
  startup_script = <<-EOT
    #!/bin/bash
    set -e
    
    # Ensure user mise config exists
    mkdir -p ~/.config/mise
    touch ~/.config/mise/config.toml

    # Ensure project directory exists
    mkdir -p ~/project

    # Prepare user home with default files on first start
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Enable access to Docker socket
    if [ -e /var/run/docker.sock ]; then
      echo "Granting access to Docker socket..."
      sudo chmod 666 /var/run/docker.sock
    fi
  EOT

  # Metadata: System Stats
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }
}

# Link OpenCode to Coder Tasks UI
resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = module.opencode[count.index].task_app_id
}

# You can read the task prompt from the `coder_task` data source.
data "coder_task" "me" {}

# ------------------------------------------------------------------------------
# Modules (Apps & Tools)
# ------------------------------------------------------------------------------

module "opencode" {
  count               = data.coder_workspace.me.start_count
  source              = "github.com/shekohex/hakim//coder/modules/opencode?ref=main"
  agent_id            = coder_agent.main.id
  workdir             = local.project_dir
  auth_json           = data.coder_parameter.opencode_auth.value
  config_json         = data.coder_parameter.opencode_config.value
  install_opencode    = false
  order               = 999
  cli_app             = true
  report_tasks        = true
  subdomain           = true
  ai_prompt           = trimspace(data.coder_task.me.prompt) != "" ? trimspace("${data.coder_parameter.system_prompt.value}\n${data.coder_task.me.prompt}") : ""
  post_install_script = data.coder_parameter.setup_script.value
}

module "git-clone" {
  count    = data.coder_parameter.git_url.value != "" ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_url.value
  base_dir = "/home/coder"
}

module "dotfiles" {
  source   = "registry.coder.com/coder/dotfiles/coder"
  agent_id = coder_agent.main.id
}

module "vault" {
  count                = data.coder_parameter.enable_vault.value ? 1 : 0
  source               = "registry.coder.com/modules/vault-github/coder"
  version              = "1.0.7"
  agent_id             = coder_agent.main.id
  vault_addr           = data.coder_parameter.vault_addr[count.index].value
  coder_github_auth_id = data.coder_parameter.vault_github_auth_id[count.index].value
}

module "code-server" {
  count          = data.coder_workspace.me.start_count
  folder         = local.project_dir
  source         = "registry.coder.com/coder/code-server/coder"
  version        = "~> 1.0"
  agent_id       = coder_agent.main.id
  order          = 1
  offline        = true
  install_prefix = "/usr/local/lib/code-server"
  settings = {
    "workbench.colorTheme" : "Default Dark Modern"
  }
}



# ------------------------------------------------------------------------------
# Workspace Presets
# ------------------------------------------------------------------------------

data "coder_workspace_preset" "laravel_quick" {
  name        = "Laravel Quick Start"
  description = "PHP 8.4 + Laravel for one-off tasks"
  icon        = "/icon/php.svg"
  default     = true
  parameters = {
    "image_variant" = "php"
    "git_url"       = ""
    "system_prompt" = "You are working on a Laravel API project. Use artisan commands."
  }
}

data "coder_workspace_preset" "dotnet_quick" {
  name        = ".NET Quick Start"
  description = ".NET 10.0 for one-off tasks"
  icon        = "/icon/dotnet.svg"
  parameters = {
    "image_variant" = "dotnet"
    "git_url"       = ""
    "system_prompt" = "You are working on a .NET Web API. Use dotnet CLI."
  }
}

data "coder_workspace_preset" "js_quick" {
  name        = "Node.js/Bun Quick Start"
  description = "Node.js + Bun environment"
  icon        = "/icon/node.svg"
  parameters = {
    "image_variant" = "js"
    "git_url"       = ""
    "system_prompt" = "You are working on a JS/TS project. Use bun or npm."
  }
}

data "coder_workspace_preset" "rust_quick" {
  name        = "Rust Quick Start"
  description = "Rust environment"
  icon        = "/icon/rust.svg"
  parameters = {
    "image_variant" = "rust"
    "git_url"       = ""
    "system_prompt" = "You are working on a Rust project. Use cargo."
  }
}

data "coder_workspace_preset" "base_minimal" {
  name        = "Minimal Environment"
  description = "Base image for custom setups"
  icon        = "/icon/debian.svg"
  parameters = {
    "image_variant" = "base"
    "git_url"       = ""
    "system_prompt" = ""
  }
}

resource "coder_app" "preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/emojis/1f50e.png"
  url          = "http://localhost:${data.coder_parameter.preview_port.value}"
  share        = "authenticated"
  subdomain    = true
  open_in      = "tab"
  order        = 0
  healthcheck {
    url       = "http://localhost:${data.coder_parameter.preview_port.value}/"
    interval  = 5
    threshold = 15
  }
}

# ------------------------------------------------------------------------------
# Infrastructure (Docker)
# ------------------------------------------------------------------------------

resource "docker_network" "private_network" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = data.coder_parameter.image_variant.value == "custom" ? data.coder_parameter.image_url[count.index].value : "ghcr.io/shekohex/hakim-${data.coder_parameter.image_variant.value}:latest"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c", replace(file("${path.module}/bootstrap.sh"), "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = concat(
    ["CODER_AGENT_TOKEN=${coder_agent.main.token}"],
    ["CODER_AGENT_URL=${replace(data.coder_workspace.me.access_url, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}"],
    ["ARCH=${data.coder_provisioner.me.arch}"],
    [for k, v in local.combined_env : "${k}=${v}"]
  )

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  networks_advanced {
    name = docker_network.private_network.name
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

