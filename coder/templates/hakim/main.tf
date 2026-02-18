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
    name        = "Elixir + Phoenix"
    description = "Elixir, Phoenix, Node.js, Bun, PostgreSQL client tools."
    value       = "elixir"
    icon        = "/icon/elixir.svg"
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

data "coder_parameter" "git_user_name" {
  name         = "git_user_name"
  display_name = "Git User Name"
  default      = ""
  mutable      = true
  type         = "string"
  description  = "Optional: Set git user.name"
  icon         = "/icon/git.svg"
  order        = 24
}

data "coder_parameter" "git_user_email" {
  name         = "git_user_email"
  display_name = "Git User Email"
  default      = ""
  mutable      = true
  type         = "string"
  description  = "Optional: Set git user.email"
  icon         = "/icon/git.svg"
  order        = 25
}

data "coder_parameter" "git_global_gitconfig" {
  name         = "git_global_gitconfig"
  display_name = "Git Global Config"
  description  = "Optional: Raw gitconfig entries"
  form_type    = "textarea"
  type         = "string"
  default      = <<-EOT
[alias]
        P = "push"
        b = "branch"
        bd = "branch -D"
        c = "commit"
        co = "checkout"
        d = "diff"
        ds = "diff --staged"
        f = "fetch"
        l = "log"
        ll = "log --graph --decorate --pretty=oneline --abbrev-commit"
        p = "pull"
        s = "status"
        sw = "switch"
        swc = "switch -c"

[branch]
        autosetuprebase = "always"

; [commit]
;       gpgSign = true

[core]
        editor = "nvim"

[credential "https://gist.github.com"]
        helper = ""
        helper = "/usr/local/share/mise/shims/gh auth git-credential"

[credential "https://github.com"]
        helper = ""
        helper = "/usr/local/share/mise/shims/gh auth git-credential"

[filter "lfs"]
        clean = "git-lfs clean -- %f"
        process = "git-lfs filter-process"
        required = true
        smudge = "git-lfs smudge -- %f"


[init]
        defaultBranch = "main"
EOT
  mutable      = true
  icon         = "/icon/git.svg"
  order        = 26
}

data "coder_parameter" "git_credential_helper" {
  name         = "git_credential_helper"
  display_name = "Git Credential Helper"
  description  = "Optional: Set to libsecret to enable git-credential-libsecret"
  type         = "string"
  default      = "store"
  mutable      = true
  icon         = "/icon/git.svg"
  order        = 27
}

data "coder_parameter" "enable_coder_login" {
  name         = "enable_coder_login"
  display_name = "Enable Coder Login"
  description  = "Auto-login to Coder in the workspace shell."
  type         = "bool"
  default      = true
  icon         = "/icon/coder.svg"
  order        = 62
}

data "coder_parameter" "enable_git_commit_signing" {
  name         = "enable_git_commit_signing"
  display_name = "Enable Git Commit Signing"
  description  = "Use Coder SSH key for Git SSH commit signing."
  type         = "bool"
  default      = true
  icon         = "/icon/git.svg"
  order        = 63
}

data "coder_parameter" "enable_zed" {
  name         = "enable_zed"
  display_name = "Enable Zed"
  description  = "Show Zed launcher app in workspace apps."
  type         = "bool"
  default      = true
  icon         = "/icon/zed.svg"
  order        = 64
}

data "coder_parameter" "enable_tmux" {
  name         = "enable_tmux"
  display_name = "Enable tmux"
  description  = "Install and configure tmux with persistence plugins."
  type         = "bool"
  default      = true
  icon         = "/icon/terminal.svg"
  order        = 65
}

data "coder_parameter" "tmux_sessions" {
  count        = data.coder_parameter.enable_tmux.value ? 1 : 0
  name         = "tmux_sessions"
  display_name = "tmux Sessions"
  description  = "Comma-separated sessions (e.g. default,dev,ops)."
  type         = "string"
  default      = "default"
  mutable      = true
  icon         = "/icon/terminal.svg"
  order        = 66
}

data "coder_parameter" "tmux_config" {
  count        = data.coder_parameter.enable_tmux.value ? 1 : 0
  name         = "tmux_config"
  display_name = "tmux Config"
  description  = "Optional custom ~/.tmux.conf content."
  type         = "string"
  form_type    = "textarea"
  default      = ""
  mutable      = true
  icon         = "/icon/terminal.svg"
  order        = 67
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

data "coder_parameter" "openchamber_ui_password" {
  name         = "openchamber_ui_password"
  display_name = "OpenChamber UI Password"
  description  = "Optional password for the OpenChamber UI."
  type         = "string"
  default      = ""
  mutable      = true
  styling      = jsonencode({ mask_input = true })
  icon         = "https://raw.githubusercontent.com/btriapitsyn/openchamber/refs/heads/main/docs/references/badges/openchamber-logo-dark.svg"
  order        = 6
}

data "coder_parameter" "openchamber_reuse_opencode" {
  name         = "openchamber_reuse_opencode"
  display_name = "OpenChamber: Reuse External OpenCode"
  description  = "When enabled, OpenChamber will connect to an external OpenCode server instead of starting its own. All connections will share the same OpenCode state."
  type         = "bool"
  default      = true
  mutable      = true
  icon         = "https://opencode.ai/favicon-96x96-v3.png"
  order        = 7
}

data "coder_parameter" "openchamber_opencode_port" {
  name         = "openchamber_opencode_port"
  display_name = "OpenChamber: OpenCode Server Port"
  description  = "Port of the external OpenCode server to connect to (only used when 'Reuse External OpenCode' is enabled)."
  type         = "number"
  default      = 4096
  mutable      = true
  icon         = "https://opencode.ai/favicon-96x96-v3.png"
  order        = 8
}

data "coder_parameter" "enable_openclaw_node" {
  name         = "enable_openclaw_node"
  display_name = "Enable OpenClaw Node Host"
  description  = "Run an OpenClaw node host in this workspace and connect it to a remote gateway bridge."
  type         = "bool"
  default      = false
  icon         = "https://raw.githubusercontent.com/openclaw/openclaw/refs/heads/main/docs/assets/pixel-lobster.svg"
  order        = 17
}

data "coder_parameter" "openclaw_bridge_host" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_bridge_host"
  display_name = "OpenClaw Bridge Host"
  description  = "Remote gateway bridge host (LAN/tailnet)."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/network.svg"
  order        = 18
}

data "coder_parameter" "openclaw_bridge_port" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_bridge_port"
  display_name = "OpenClaw Bridge Port"
  description  = "Remote gateway bridge port."
  type         = "number"
  default      = 18790
  mutable      = true
  icon         = "/icon/network.svg"
  order        = 19
}

data "coder_parameter" "openclaw_bridge_tls" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_bridge_tls"
  display_name = "OpenClaw Bridge TLS"
  description  = "Use TLS when connecting to the bridge."
  type         = "bool"
  default      = false
  icon         = "/icon/lock.svg"
  order        = 20
}

data "coder_parameter" "openclaw_bridge_tls_fingerprint" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_bridge_tls_fingerprint"
  display_name = "OpenClaw Bridge TLS Fingerprint"
  description  = "Optional SHA256 fingerprint to pin the bridge certificate."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/lock.svg"
  order        = 21
}

data "coder_parameter" "openclaw_gateway_ws_url" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_gateway_ws_url"
  display_name = "OpenClaw Gateway WS URL"
  description  = "Optional: ws://host:18789 used only for auto-approving pairing."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/link.svg"
  order        = 22
}

data "coder_parameter" "openclaw_gateway_token" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_gateway_token"
  display_name = "OpenClaw Gateway Token"
  description  = "Optional: gateway token used only for auto-approving pairing."
  type         = "string"
  default      = ""
  mutable      = true
  styling      = jsonencode({ mask_input = true })
  icon         = "/icon/lock.svg"
  order        = 23
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

data "coder_parameter" "enable_resource_limits" {
  name         = "enable_resource_limits"
  display_name = "Enable Resource Limits"
  description  = "Configure CPU and memory limits for the container."
  type         = "bool"
  default      = false
  icon         = "/icon/memory.svg"
  order        = 14
}

data "coder_parameter" "container_memory" {
  count        = data.coder_parameter.enable_resource_limits.value ? 1 : 0
  name         = "container_memory"
  display_name = "Memory Limit (MB)"
  description  = "Hard memory limit in MB. 0 = unlimited."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 15
}

data "coder_parameter" "container_cpus" {
  count        = data.coder_parameter.enable_resource_limits.value ? 1 : 0
  name         = "container_cpus"
  display_name = "CPU Limit"
  description  = "CPU cores limit (e.g., 2 or 1.5). 0 = unlimited."
  type         = "string"
  default      = "0"
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 16
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
  user_env   = try(jsondecode(trimspace(data.coder_parameter.user_env.value)), {})
  secret_env = try(jsondecode(trimspace(data.coder_parameter.secret_env.value)), {})
  default_env = {
    MIX_HOME     = "/home/coder/.mix"
    HEX_HOME     = "/home/coder/.hex"
    MIX_ARCHIVES = "/home/coder/.mix/archives"
  }
  combined_env        = merge(local.default_env, local.user_env, local.secret_env)
  project_dir         = length(module.git-clone) > 0 ? module.git-clone[0].repo_dir : "/home/coder/project"
  git_setup_script    = file("${path.module}/scripts/setup-git.sh")
  tmux_sessions_raw   = length(data.coder_parameter.tmux_sessions) > 0 ? data.coder_parameter.tmux_sessions[0].value : "default"
  tmux_sessions_clean = [for session in split(",", local.tmux_sessions_raw) : trimspace(session) if trimspace(session) != ""]
  tmux_sessions       = length(local.tmux_sessions_clean) > 0 ? local.tmux_sessions_clean : ["default"]
  tmux_config         = length(data.coder_parameter.tmux_config) > 0 ? data.coder_parameter.tmux_config[0].value : ""
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
  install_opencode    = true
  order               = 999
  cli_app             = true
  report_tasks        = true
  subdomain           = true
  ai_prompt           = trimspace(data.coder_task.me.prompt) != "" ? trimspace("${data.coder_parameter.system_prompt.value}\n${data.coder_task.me.prompt}") : ""
  post_install_script = data.coder_parameter.setup_script.value
}

module "openchamber" {
  count = data.coder_workspace.me.start_count > 0 && contains([
    "php",
    "dotnet",
    "js",
    "rust",
    "elixir"
  ], data.coder_parameter.image_variant.value) ? 1 : 0
  source                = "github.com/shekohex/hakim//coder/modules/openchamber?ref=main"
  agent_id              = coder_agent.main.id
  workdir               = local.project_dir
  ui_password           = data.coder_parameter.openchamber_ui_password.value
  reuse_opencode_server = data.coder_parameter.openchamber_reuse_opencode.value
  opencode_port         = data.coder_parameter.openchamber_opencode_port.value
  install_openchamber   = true
  order                 = 998
  subdomain             = true
  depends_on            = [module.opencode]
}

module "openclaw_node" {
  count = (
    data.coder_workspace.me.start_count > 0 &&
    data.coder_parameter.enable_openclaw_node.value &&
    contains(["php", "dotnet", "js", "rust", "elixir"], data.coder_parameter.image_variant.value) &&
    length(data.coder_parameter.openclaw_bridge_host) > 0 &&
    trimspace(data.coder_parameter.openclaw_bridge_host[0].value) != ""
  ) ? 1 : 0

  source                 = "github.com/shekohex/hakim//coder/modules/openclaw-node?ref=main"
  agent_id               = coder_agent.main.id
  install_openclaw       = false
  bridge_host            = data.coder_parameter.openclaw_bridge_host[0].value
  bridge_port            = data.coder_parameter.openclaw_bridge_port[0].value
  bridge_tls             = data.coder_parameter.openclaw_bridge_tls[0].value
  bridge_tls_fingerprint = data.coder_parameter.openclaw_bridge_tls_fingerprint[0].value
  display_name           = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  gateway_ws_url         = length(data.coder_parameter.openclaw_gateway_ws_url) > 0 ? data.coder_parameter.openclaw_gateway_ws_url[0].value : ""
  gateway_token          = length(data.coder_parameter.openclaw_gateway_token) > 0 ? data.coder_parameter.openclaw_gateway_token[0].value : ""
  auto_approve_pairing = (
    length(data.coder_parameter.openclaw_gateway_ws_url) > 0 &&
    trimspace(data.coder_parameter.openclaw_gateway_ws_url[0].value) != "" &&
    length(data.coder_parameter.openclaw_gateway_token) > 0 &&
    trimspace(data.coder_parameter.openclaw_gateway_token[0].value) != ""
  )
  order      = 997
  depends_on = [module.opencode]
}

module "git-clone" {
  count      = data.coder_parameter.git_url.value != "" ? 1 : 0
  source     = "registry.coder.com/coder/git-clone/coder"
  agent_id   = coder_agent.main.id
  url        = data.coder_parameter.git_url.value
  base_dir   = "/home/coder"
  depends_on = [coder_script.git_setup]
}

module "dotfiles" {
  source   = "registry.coder.com/coder/dotfiles/coder"
  agent_id = coder_agent.main.id
}

module "coder-login" {
  count    = data.coder_parameter.enable_coder_login.value ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

module "git-commit-signing" {
  count      = data.coder_parameter.enable_git_commit_signing.value ? data.coder_workspace.me.start_count : 0
  source     = "github.com/shekohex/hakim//coder/modules/git-commit-signing?ref=main"
  agent_id   = coder_agent.main.id
  depends_on = [coder_script.git_setup]
}

module "zed" {
  count    = data.coder_parameter.enable_zed.value ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.4"
  agent_id = coder_agent.main.id
  folder   = local.project_dir
  order    = 0
}

module "tmux" {
  count       = data.coder_parameter.enable_tmux.value ? data.coder_workspace.me.start_count : 0
  source      = "registry.coder.com/anomaly/tmux/coder"
  version     = "1.0.4"
  agent_id    = coder_agent.main.id
  sessions    = local.tmux_sessions
  tmux_config = local.tmux_config
}

resource "coder_script" "git_setup" {
  agent_id     = coder_agent.main.id
  display_name = "Configure Git"
  icon         = "/icon/git.svg"
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    SETUP_SCRIPT="/tmp/git-setup-$$.sh"
    echo -n '${base64encode(local.git_setup_script)}' | base64 -d > "$SETUP_SCRIPT"
    chmod +x "$SETUP_SCRIPT"

    ARG_GIT_USER_NAME='${data.coder_parameter.git_user_name.value != "" ? base64encode(replace(data.coder_parameter.git_user_name.value, "'", "'\\''")) : ""}' \
    ARG_GIT_USER_EMAIL='${data.coder_parameter.git_user_email.value != "" ? base64encode(replace(data.coder_parameter.git_user_email.value, "'", "'\\''")) : ""}' \
    ARG_GIT_GLOBAL_GITCONFIG='${data.coder_parameter.git_global_gitconfig.value != "" ? base64encode(data.coder_parameter.git_global_gitconfig.value) : ""}' \
    ARG_GIT_CREDENTIAL_HELPER='${data.coder_parameter.git_credential_helper.value}' \
    "$SETUP_SCRIPT"

    rm -f "$SETUP_SCRIPT"
  EOT
  run_on_start = true
  depends_on   = [module.dotfiles]
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

data "coder_workspace_preset" "phoenix_quick" {
  name        = "Phoenix Quick Start"
  description = "Elixir + Phoenix environment"
  icon        = "/icon/docker.svg"
  parameters = {
    "image_variant" = "elixir"
    "git_url"       = ""
    "system_prompt" = "You are working on a Phoenix project. Use mix, phx, and Ecto commands. Prefer mix format and ElixirLS."
    "preview_port"  = "4000"
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

  memory = (
    data.coder_parameter.enable_resource_limits.value &&
    length(data.coder_parameter.container_memory) > 0 &&
    data.coder_parameter.container_memory[0].value > 0
  ) ? data.coder_parameter.container_memory[0].value : null

  cpus = (
    data.coder_parameter.enable_resource_limits.value &&
    length(data.coder_parameter.container_cpus) > 0 &&
    tonumber(data.coder_parameter.container_cpus[0].value) > 0
  ) ? data.coder_parameter.container_cpus[0].value : null

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
