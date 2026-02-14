terraform {
  required_version = ">= 1.4"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = data.coder_parameter.proxmox_endpoint.value
  api_token = data.coder_parameter.proxmox_api_token.value
  insecure  = data.coder_parameter.proxmox_insecure.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

data "coder_parameter" "image_variant" {
  name         = "image_variant"
  display_name = "Environment"
  description  = "Select the programming language environment."
  default      = "base"
  type         = "string"
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
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
    description = "Specify a custom template id below"
    value       = "custom"
  }
  order = 1
}

data "coder_parameter" "custom_template_file_id" {
  count        = data.coder_parameter.image_variant.value == "custom" ? 1 : 0
  name         = "custom_template_file_id"
  display_name = "Custom Template File ID"
  description  = "Proxmox template volume id, e.g. local:vztmpl/hakim-base_latest.tar"
  default      = ""
  mutable      = true
  type         = "string"
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 2
}

data "coder_parameter" "template_tag" {
  count        = data.coder_parameter.image_variant.value == "custom" ? 0 : 1
  name         = "template_tag"
  display_name = "Template Tag"
  description  = "Pre-pulled template tag suffix. Expects hakim-<variant>_<tag>.tar in template datastore."
  default      = "latest"
  mutable      = true
  type         = "string"
  icon         = "https://esm.sh/lucide-static@latest/icons/tag.svg"
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

data "coder_parameter" "system_prompt" {
  name         = "system_prompt"
  display_name = "System Prompt"
  type         = "string"
  form_type    = "textarea"
  description  = "System prompt for the AI agent."
  default      = ""
  mutable      = true
  icon         = "/icon/tasks.svg"
  order        = 7
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
  order        = 8
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
  order        = 9
}

data "coder_parameter" "enable_vault" {
  name         = "enable_vault"
  display_name = "Enable Vault CLI"
  description  = "Install and auth Vault via GitHub token."
  type         = "bool"
  default      = false
  icon         = "/icon/vault.svg"
  order        = 10
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
  order        = 11
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
  order        = 12
}

data "coder_parameter" "preview_port" {
  name         = "preview_port"
  display_name = "Preview Port"
  description  = "The port the web app is running to preview in Tasks."
  type         = "number"
  default      = 3000
  mutable      = true
  icon         = "/icon/widgets.svg"
  order        = 13
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
  order        = 14
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
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
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
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
  order        = 19
}

data "coder_parameter" "openclaw_bridge_tls" {
  count        = data.coder_parameter.enable_openclaw_node.value ? 1 : 0
  name         = "openclaw_bridge_tls"
  display_name = "OpenClaw Bridge TLS"
  description  = "Use TLS when connecting to the bridge."
  type         = "bool"
  default      = false
  icon         = "https://esm.sh/lucide-static@latest/icons/lock.svg"
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
  icon         = "https://esm.sh/lucide-static@latest/icons/lock.svg"
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
  icon         = "https://esm.sh/lucide-static@latest/icons/link.svg"
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
  icon         = "https://esm.sh/lucide-static@latest/icons/lock.svg"
  order        = 23
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

data "coder_parameter" "proxmox_endpoint" {
  name         = "proxmox_endpoint"
  display_name = "Proxmox Endpoint"
  description  = "Proxmox API endpoint, e.g. https://pve.example.com:8006/"
  type         = "string"
  default      = "https://proxmox.example.com:8006/"
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 30
}

data "coder_parameter" "proxmox_api_token" {
  name         = "proxmox_api_token"
  display_name = "Proxmox API Token"
  description  = "API token in the form user@realm!tokenid=secret"
  type         = "string"
  default      = "root@pam!coder-template=dummy"
  mutable      = true
  styling      = jsonencode({ mask_input = true })
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 31
}

data "coder_parameter" "proxmox_insecure" {
  name         = "proxmox_insecure"
  display_name = "Skip TLS Verify"
  description  = "Skip TLS verification for the Proxmox API."
  type         = "bool"
  default      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/lock.svg"
  order        = 32
}

data "coder_parameter" "proxmox_node_name" {
  name         = "proxmox_node_name"
  display_name = "Proxmox Node"
  description  = "Proxmox node name where the container runs."
  type         = "string"
  default      = "pve"
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 33
}

data "coder_parameter" "proxmox_pool_id" {
  name         = "proxmox_pool_id"
  display_name = "Pool ID"
  description  = "Optional Proxmox pool id."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 34
}

data "coder_parameter" "proxmox_container_datastore_id" {
  name         = "proxmox_container_datastore_id"
  display_name = "Container Datastore"
  description  = "Datastore for container rootfs."
  type         = "string"
  default      = "local-lvm"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 35
}

data "coder_parameter" "proxmox_template_datastore_id" {
  name         = "proxmox_template_datastore_id"
  display_name = "Template Datastore"
  description  = "Datastore containing pre-pulled OCI-derived vztmpl templates."
  type         = "string"
  default      = "local"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 36
}

data "coder_parameter" "proxmox_network_bridge" {
  name         = "proxmox_network_bridge"
  display_name = "Network Bridge"
  description  = "Bridge to attach the container NIC."
  type         = "string"
  default      = "vmbr0"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
  order        = 37
}

data "coder_parameter" "proxmox_vlan_id" {
  name         = "proxmox_vlan_id"
  display_name = "VLAN ID"
  description  = "Optional VLAN id. Use 0 to disable."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
  order        = 38
}

data "coder_parameter" "proxmox_network_firewall" {
  name         = "proxmox_network_firewall"
  display_name = "Enable NIC Firewall"
  description  = "Enable Proxmox firewall flag on the primary NIC."
  type         = "bool"
  default      = false
  icon         = "https://esm.sh/lucide-static@latest/icons/shield.svg"
  order        = 39
}

data "coder_parameter" "proxmox_vm_id" {
  name         = "proxmox_vm_id"
  display_name = "Container ID"
  description  = "Optional fixed VM/CT id. Use 0 for auto-allocation."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 40
}

data "coder_parameter" "container_memory_mb" {
  name         = "container_memory_mb"
  display_name = "Memory (MB)"
  description  = "Dedicated memory for the container."
  type         = "number"
  default      = 4096
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 41
}

data "coder_parameter" "container_cores" {
  name         = "container_cores"
  display_name = "CPU Cores"
  description  = "CPU cores for the container."
  type         = "number"
  default      = 2
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 42
}

data "coder_parameter" "container_disk_gb" {
  name         = "container_disk_gb"
  display_name = "Root Disk (GB)"
  description  = "Root disk size in GB."
  type         = "number"
  default      = 20
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 43
}

data "coder_parameter" "enable_home_disk" {
  name         = "enable_home_disk"
  display_name = "Enable Home Disk"
  description  = "Attach a dedicated volume at /home/coder."
  type         = "bool"
  default      = false
  icon         = "https://esm.sh/lucide-static@latest/icons/hard-drive.svg"
  order        = 56
}

data "coder_parameter" "home_disk_gb" {
  count        = data.coder_parameter.enable_home_disk.value ? 1 : 0
  name         = "home_disk_gb"
  display_name = "Home Disk (GB)"
  description  = "Size of /home/coder volume."
  type         = "number"
  default      = 30
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/hard-drive.svg"
  order        = 57
}

data "coder_parameter" "proxmox_home_datastore_id" {
  count        = data.coder_parameter.enable_home_disk.value ? 1 : 0
  name         = "proxmox_home_datastore_id"
  display_name = "Home Datastore"
  description  = "Optional datastore for /home/coder volume. Empty uses container datastore."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 58
}

data "coder_parameter" "proxmox_home_volume_id" {
  count        = data.coder_parameter.enable_home_disk.value ? 1 : 0
  name         = "proxmox_home_volume_id"
  display_name = "Existing Home Volume ID"
  description  = "Optional existing volume id to mount at /home/coder (for rebuild/migration)."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/link.svg"
  order        = 59
}

data "coder_parameter" "workspace_rebuild_generation" {
  name         = "workspace_rebuild_generation"
  display_name = "Workspace Rebuild Generation"
  description  = "Increment to force container recreation and pick up a refreshed template."
  type         = "number"
  default      = 1
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/refresh-cw.svg"
  order        = 60
}

data "coder_parameter" "enable_nesting" {
  name         = "enable_nesting"
  display_name = "Enable Nesting"
  description  = "Enable LXC nesting. Disabled by default."
  type         = "bool"
  default      = false
  icon         = "https://esm.sh/lucide-static@latest/icons/shield.svg"
  order        = 44
}

data "coder_parameter" "egress_mode" {
  name         = "egress_mode"
  display_name = "Egress Mode"
  description  = "Network egress policy hint."
  type         = "string"
  default      = "open"
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
  option {
    name  = "Open"
    value = "open"
  }
  option {
    name  = "Restricted"
    value = "restricted"
  }
  option {
    name  = "Airgapped"
    value = "airgapped"
  }
  order = 45
}

locals {
  user_env   = try(jsondecode(trimspace(data.coder_parameter.user_env.value)), {})
  secret_env = try(jsondecode(trimspace(data.coder_parameter.secret_env.value)), {})
  default_env = {
    PATH         = "/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    LANG         = "C.UTF-8"
    LANGUAGE     = "C.UTF-8"
    LC_ALL       = "C.UTF-8"
    MIX_HOME     = "/home/coder/.mix"
    HEX_HOME     = "/home/coder/.hex"
    MIX_ARCHIVES = "/home/coder/.mix/archives"
  }
  combined_env = merge(local.default_env, local.user_env, local.secret_env)

  selected_template_tag = length(data.coder_parameter.template_tag) > 0 && trimspace(data.coder_parameter.template_tag[0].value) != "" ? trimspace(data.coder_parameter.template_tag[0].value) : "latest"
  selected_template_file_id = data.coder_parameter.image_variant.value == "custom" ? data.coder_parameter.custom_template_file_id[0].value : (
    "${data.coder_parameter.proxmox_template_datastore_id.value}:vztmpl/hakim-${data.coder_parameter.image_variant.value}_${local.selected_template_tag}.tar"
  )

  container_environment_variables = local.combined_env
  container_agent_bootstrap       = base64encode("${data.coder_workspace.me.access_url}|${coder_agent.main.token}")

  home_disk_enabled        = data.coder_parameter.enable_home_disk.value && length(data.coder_parameter.home_disk_gb) > 0 && data.coder_parameter.home_disk_gb[0].value > 0
  home_volume_id           = length(data.coder_parameter.proxmox_home_volume_id) > 0 ? trimspace(data.coder_parameter.proxmox_home_volume_id[0].value) : ""
  home_datastore_id        = length(data.coder_parameter.proxmox_home_datastore_id) > 0 && trimspace(data.coder_parameter.proxmox_home_datastore_id[0].value) != "" ? trimspace(data.coder_parameter.proxmox_home_datastore_id[0].value) : data.coder_parameter.proxmox_container_datastore_id.value
  use_existing_home_volume = local.home_volume_id != ""
  home_disk_size           = local.home_disk_enabled ? "${data.coder_parameter.home_disk_gb[0].value}G" : null

  project_dir      = length(module.git-clone) > 0 ? module.git-clone[0].repo_dir : "/home/coder/project"
  git_setup_script = file("${path.module}/scripts/setup-git.sh")
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  env  = local.combined_env

  startup_script = <<-EOT
    #!/bin/bash
    set -e
    mkdir -p ~/.config/mise
    touch ~/.config/mise/config.toml
    mkdir -p ~/project
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
    fi
  EOT

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

resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = module.opencode[count.index].task_app_id
}

data "coder_task" "me" {}

resource "terraform_data" "workspace_rebuild_generation" {
  input = data.coder_parameter.workspace_rebuild_generation.value

  triggers_replace = [
    data.coder_parameter.workspace_rebuild_generation.value
  ]
}

resource "proxmox_virtual_environment_container" "workspace" {
  node_name             = data.coder_parameter.proxmox_node_name.value
  vm_id                 = data.coder_parameter.proxmox_vm_id.value > 0 ? data.coder_parameter.proxmox_vm_id.value : null
  pool_id               = trimspace(data.coder_parameter.proxmox_pool_id.value) != "" ? data.coder_parameter.proxmox_pool_id.value : null
  description           = "Coder workspace ${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"
  unprivileged          = true
  started               = data.coder_workspace.me.transition == "start"
  start_on_boot         = false
  tags                  = ["coder", "hakim", data.coder_parameter.image_variant.value, data.coder_parameter.egress_mode.value, "template-${local.selected_template_tag}"]
  environment_variables = local.container_environment_variables
  lifecycle {
    replace_triggered_by = [terraform_data.workspace_rebuild_generation]

    precondition {
      condition     = data.coder_parameter.image_variant.value != "custom" || trimspace(data.coder_parameter.custom_template_file_id[0].value) != ""
      error_message = "custom_template_file_id must be set when image_variant is custom."
    }
  }
  cpu {
    cores = data.coder_parameter.container_cores.value
  }

  memory {
    dedicated = data.coder_parameter.container_memory_mb.value
    swap      = 0
  }

  disk {
    datastore_id = data.coder_parameter.proxmox_container_datastore_id.value
    size         = data.coder_parameter.container_disk_gb.value
  }

  dynamic "mount_point" {
    for_each = local.home_disk_enabled ? [1] : []

    content {
      path   = "/home/coder"
      volume = local.use_existing_home_volume ? local.home_volume_id : local.home_datastore_id
      size   = local.use_existing_home_volume ? null : local.home_disk_size
      backup = true
    }
  }

  operating_system {
    template_file_id = local.selected_template_file_id
    type             = data.coder_parameter.image_variant.value == "custom" ? "unmanaged" : "debian"
  }

  features {
    nesting = data.coder_parameter.enable_nesting.value
  }

  initialization {
    hostname = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = data.coder_parameter.proxmox_network_bridge.value
    vlan_id  = data.coder_parameter.proxmox_vlan_id.value > 0 ? data.coder_parameter.proxmox_vlan_id.value : null
    firewall = data.coder_parameter.proxmox_network_firewall.value
  }

  wait_for_ip {
    ipv4 = true
  }

}

resource "terraform_data" "workspace_agent_env" {
  count = data.coder_workspace.me.start_count

  triggers_replace = {
    node_name       = data.coder_parameter.proxmox_node_name.value
    vm_id           = tostring(proxmox_virtual_environment_container.workspace.vm_id)
    endpoint        = trimsuffix(data.coder_parameter.proxmox_endpoint.value, "/")
    insecure        = tostring(data.coder_parameter.proxmox_insecure.value)
    agent_url       = data.coder_workspace.me.access_url
    agent_token_sha = sha256(coder_agent.main.token)
    env_sha         = sha256(jsonencode(local.combined_env))
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/bootstrap-agent-env.sh"

    environment = {
      PVE_ENDPOINT       = trimsuffix(data.coder_parameter.proxmox_endpoint.value, "/")
      PVE_NODE_NAME      = data.coder_parameter.proxmox_node_name.value
      PVE_VM_ID          = tostring(proxmox_virtual_environment_container.workspace.vm_id)
      PVE_API_TOKEN      = data.coder_parameter.proxmox_api_token.value
      PVE_INSECURE       = tostring(data.coder_parameter.proxmox_insecure.value)
      CT_AGENT_BOOTSTRAP = local.container_agent_bootstrap
    }
  }

  depends_on = [proxmox_virtual_environment_container.workspace]
}

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
  depends_on          = [terraform_data.workspace_agent_env]
}

module "openchamber" {
  count = data.coder_workspace.me.start_count > 0 && contains([
    "php",
    "dotnet",
    "js",
    "rust",
    "elixir"
  ], data.coder_parameter.image_variant.value) ? 1 : 0

  source              = "github.com/shekohex/hakim//coder/modules/openchamber?ref=main"
  agent_id            = coder_agent.main.id
  workdir             = local.project_dir
  ui_password         = data.coder_parameter.openchamber_ui_password.value
  install_openchamber = true
  order               = 998
  subdomain           = true
  depends_on          = [module.opencode]
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
