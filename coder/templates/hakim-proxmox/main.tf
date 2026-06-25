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
  api_token = local.requires_root_session ? null : data.coder_parameter.proxmox_api_token.value
  username  = local.requires_root_session ? trimspace(data.coder_parameter.proxmox_username.value) : null
  password  = local.requires_root_session ? data.coder_parameter.proxmox_password.value : null
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
    name        = "Android"
    description = "Android SDK, Java 17, NDK r29, and modern build tooling."
    value       = "android"
    icon        = "https://cdn.simpleicons.org/android?viewbox=auto"
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

data "coder_parameter" "enable_ssh_keys" {
  name         = "enable_ssh_keys"
  display_name = "Enable SSH Keys"
  description  = "Install the Coder SSH key as ~/.ssh/id_ed25519 for outbound SSH."
  type         = "bool"
  default      = false
  icon         = "/icon/terminal.svg"
  order        = 64
}

data "coder_parameter" "enable_zed" {
  name         = "enable_zed"
  display_name = "Enable Zed"
  description  = "Show Zed launcher app in workspace apps."
  type         = "bool"
  default      = true
  icon         = "/icon/zed.svg"
  order        = 65
}

data "coder_parameter" "enable_tmux" {
  name         = "enable_tmux"
  display_name = "Enable tmux"
  description  = "Install and configure tmux with persistence plugins."
  type         = "bool"
  default      = true
  icon         = "/icon/terminal.svg"
  order        = 66
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
  order        = 67
}

data "coder_parameter" "tmux_config" {
  count        = data.coder_parameter.enable_tmux.value ? 1 : 0
  name         = "tmux_config"
  display_name = "tmux Config"
  description  = "Optional custom ~/.tmux.conf content. Leave empty to keep template defaults."
  type         = "string"
  form_type    = "textarea"
  default      = trimspace(file("${path.module}/tmux.conf"))
  mutable      = true
  icon         = "/icon/terminal.svg"
  order        = 68
}

data "coder_parameter" "enable_et" {
  name         = "enable_et"
  display_name = "Enable EternalTerminal"
  description  = "Run loopback etserver (2022) + hardened sshd (2244) for resilient SSH sessions."
  type         = "bool"
  default      = true
  icon         = "/icon/terminal.svg"
  order        = 69
}

data "coder_parameter" "shekohex_agent_auth" {
  name         = "shekohex_agent_auth"
  display_name = "Shekohex Agent Auth JSON"
  description  = "Paste content of ~/.pi/agent/auth.json"
  form_type    = "textarea"
  type         = "string"
  default      = "{}"
  mutable      = true
  styling      = jsonencode({ mask_input = true })
  icon         = "/icon/terminal.svg"
  order        = 4
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

data "coder_parameter" "system_prompt" {
  name         = "system_prompt"
  display_name = "System Prompt"
  type         = "string"
  form_type    = "textarea"
  description  = "System prompt for workspace tasks."
  default      = ""
  mutable      = true
  icon         = "/icon/tasks.svg"
  order        = 6
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

data "coder_parameter" "proxmox_username" {
  name         = "proxmox_username"
  display_name = "Proxmox Username"
  description  = "Used for bind mounts; must be root@pam."
  type         = "string"
  default      = "root@pam"
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 32
}

data "coder_parameter" "proxmox_password" {
  name         = "proxmox_password"
  display_name = "Proxmox Password"
  description  = "Used for bind mounts."
  type         = "string"
  default      = ""
  mutable      = true
  styling      = jsonencode({ mask_input = true })
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 33
}

data "coder_parameter" "proxmox_insecure" {
  name         = "proxmox_insecure"
  display_name = "Skip TLS Verify"
  description  = "Skip TLS verification for the Proxmox API."
  type         = "bool"
  default      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/lock.svg"
  order        = 34
}

data "coder_parameter" "proxmox_node_name" {
  name         = "proxmox_node_name"
  display_name = "Proxmox Node"
  description  = "Proxmox node name where the container runs."
  type         = "string"
  default      = "pve"
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 35
}

data "coder_parameter" "proxmox_pool_id" {
  name         = "proxmox_pool_id"
  display_name = "Pool ID"
  description  = "Optional Proxmox pool id."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 36
}

data "coder_parameter" "proxmox_container_datastore_id" {
  name         = "proxmox_container_datastore_id"
  display_name = "Container Datastore"
  description  = "Datastore for container rootfs."
  type         = "string"
  default      = "local-lvm"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 37
}

data "coder_parameter" "proxmox_template_datastore_id" {
  name         = "proxmox_template_datastore_id"
  display_name = "Template Datastore"
  description  = "Datastore containing pre-pulled OCI-derived vztmpl templates."
  type         = "string"
  default      = "local"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 38
}

data "coder_parameter" "proxmox_network_bridge" {
  name         = "proxmox_network_bridge"
  display_name = "Network Bridge"
  description  = "Bridge to attach the container NIC."
  type         = "string"
  default      = "vmbr0"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
  order        = 39
}

data "coder_parameter" "proxmox_vlan_id" {
  name         = "proxmox_vlan_id"
  display_name = "VLAN ID"
  description  = "Optional VLAN id. Use 0 to disable."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/network.svg"
  order        = 40
}

data "coder_parameter" "proxmox_network_firewall" {
  name         = "proxmox_network_firewall"
  display_name = "Enable NIC Firewall"
  description  = "Enable Proxmox firewall flag on the primary NIC."
  type         = "bool"
  default      = false
  icon         = "https://esm.sh/lucide-static@latest/icons/shield.svg"
  order        = 41
}

data "coder_parameter" "proxmox_vm_id" {
  name         = "proxmox_vm_id"
  display_name = "Container ID"
  description  = "Optional fixed VM/CT id. Use 0 for auto-allocation."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "https://cdn.simpleicons.org/proxmox?viewbox=auto"
  order        = 42
}

data "coder_parameter" "container_memory_mb" {
  name         = "container_memory_mb"
  display_name = "Memory (MB)"
  description  = "Dedicated memory for the container."
  type         = "number"
  default      = 4096
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 43
}

data "coder_parameter" "enable_container_swap" {
  name         = "enable_container_swap"
  display_name = "Enable Swap"
  description  = "Enable swap for the container."
  type         = "bool"
  default      = true
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 44
}

data "coder_parameter" "container_swap_mb" {
  count        = data.coder_parameter.enable_container_swap.value ? 1 : 0
  name         = "container_swap_mb"
  display_name = "Swap Size (MB)"
  description  = "Additional swap in MB. 0 = 50% of the memory size."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 45
}

data "coder_parameter" "container_cores" {
  name         = "container_cores"
  display_name = "CPU Cores"
  description  = "CPU cores for the container."
  type         = "number"
  default      = 2
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 46
}

data "coder_parameter" "container_disk_gb" {
  name         = "container_disk_gb"
  display_name = "Root Disk (GB)"
  description  = "Root disk size in GB."
  type         = "number"
  default      = 20
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 47
}

data "coder_parameter" "enable_home_disk" {
  name         = "enable_home_disk"
  display_name = "Enable Home Persistence"
  description  = "Persist /home/coder using lifecycle-safe Proxmox storage independent from CT replacement."
  type         = "bool"
  default      = false
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/hard-drive.svg"
  order        = 56
}

data "coder_parameter" "home_disk_gb" {
  count        = data.coder_parameter.enable_home_disk.value ? 1 : 0
  name         = "home_disk_gb"
  display_name = "Home Size (GB)"
  description  = "Size for lifecycle-safe home volumes. Existing volumes are grown when this value increases."
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
  description  = "Proxmox storage used for persistent home volumes. Defaults to NVMe-backed local-lvm."
  type         = "string"
  default      = "local-lvm"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/database.svg"
  order        = 58
}

data "coder_parameter" "proxmox_home_volume_id" {
  count        = data.coder_parameter.enable_home_disk.value ? 1 : 0
  name         = "proxmox_home_volume_id"
  display_name = "Existing Home Mount Source"
  description  = "Optional existing mount source for /home/coder (Proxmox volume id or explicit absolute bind path). Empty creates/reuses lifecycle-safe local-lvm volume."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/link.svg"
  order        = 59
}

data "coder_parameter" "home_migration_mode" {
  count        = data.coder_parameter.enable_home_disk.value ? 1 : 0
  name         = "home_migration_mode"
  display_name = "Home Migration Mode"
  description  = "Controls migration from legacy bind paths to local-lvm. Safe default copies data and keeps the old source."
  type         = "string"
  default      = "copy_keep_source"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/copy.svg"
  order        = 60

  option {
    name  = "Copy and keep source"
    value = "copy_keep_source"
  }

  option {
    name  = "Disabled"
    value = "disabled"
  }

  option {
    name  = "Fail if legacy source exists"
    value = "fail_if_legacy_source_exists"
  }
}

data "coder_parameter" "proxmox_home_bind_hook_script_id" {
  count        = (data.coder_parameter.enable_home_disk.value || data.coder_parameter.enable_docker_data_offload.value) ? 1 : 0
  name         = "proxmox_home_bind_hook_script_id"
  display_name = "Home Bind Hook Script ID"
  description  = "Proxmox hookscript volume id used to auto-create bind paths, e.g. local:snippets/hakim-home-bind-hook.sh"
  type         = "string"
  default      = "local:snippets/hakim-home-bind-hook.sh"
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/file-code.svg"
  order        = 64
}

data "coder_parameter" "enable_docker_data_offload" {
  name         = "enable_docker_data_offload"
  display_name = "Enable Docker Data Offload"
  description  = "Persist Docker data root at /home/coder/.local/share/docker using a deterministic host bind mount under /tank."
  type         = "bool"
  default      = false
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/package.svg"
  order        = 61
}

data "coder_parameter" "proxmox_docker_volume_id" {
  count        = data.coder_parameter.enable_docker_data_offload.value ? 1 : 0
  name         = "proxmox_docker_volume_id"
  display_name = "Existing Docker Mount Source"
  description  = "Optional existing mount source for Docker data root (volume id or absolute bind path). Empty uses /tank/hakim-docker/<owner>/<workspace>."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/link.svg"
  order        = 62
}

data "coder_parameter" "workspace_rebuild_generation" {
  name         = "workspace_rebuild_generation"
  display_name = "Workspace Rebuild Generation"
  description  = "Increment to force container recreation and pick up a refreshed template."
  type         = "number"
  default      = 1
  mutable      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/refresh-cw.svg"
  order        = 63
}

data "coder_parameter" "enable_nesting" {
  name         = "enable_nesting"
  display_name = "Enable Nesting"
  description  = "Enable LXC nesting for systemd, Docker, and nested runtime support."
  type         = "bool"
  default      = true
  icon         = "https://esm.sh/lucide-static@latest/icons/shield.svg"
  order        = 46
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
  order = 47
}

locals {
  user_env   = try(jsondecode(trimspace(data.coder_parameter.user_env.value)), {})
  secret_env = try(jsondecode(trimspace(data.coder_parameter.secret_env.value)), {})
  default_env = {
    PATH                  = "/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/share/mise/shims"
    LANG                  = "C.UTF-8"
    LANGUAGE              = "C.UTF-8"
    LC_ALL                = "C.UTF-8"
    MIX_HOME              = "/home/coder/.mix"
    HEX_HOME              = "/home/coder/.hex"
    MIX_ARCHIVES          = "/home/coder/.mix/archives"
    CODER_UID             = "1000"
    CODER_GID             = "1000"
    START_DOCKER_DAEMON   = "1"
    DOCKER_STORAGE_DRIVER = "vfs"
  }
  docker_data_root_env = (data.coder_parameter.enable_home_disk.value || data.coder_parameter.enable_docker_data_offload.value) ? {
    DOCKER_DATA_ROOT = "/home/coder/.local/share/docker"
  } : {}
  combined_env            = merge(local.default_env, local.docker_data_root_env, local.user_env, local.secret_env)
  container_swap_enabled  = data.coder_parameter.enable_container_swap.value
  container_swap_mb_input = local.container_swap_enabled && length(data.coder_parameter.container_swap_mb) > 0 ? data.coder_parameter.container_swap_mb[0].value : 0
  container_swap_mb       = local.container_swap_enabled ? (local.container_swap_mb_input > 0 ? local.container_swap_mb_input : ceil(data.coder_parameter.container_memory_mb.value * 0.5)) : 0
  workspace_agent_count   = data.coder_workspace.me.transition == "start" ? 1 : 0

  selected_template_tag = length(data.coder_parameter.template_tag) > 0 && trimspace(data.coder_parameter.template_tag[0].value) != "" ? trimspace(data.coder_parameter.template_tag[0].value) : "latest"
  selected_template_file_id = data.coder_parameter.image_variant.value == "custom" ? data.coder_parameter.custom_template_file_id[0].value : (
    "${data.coder_parameter.proxmox_template_datastore_id.value}:vztmpl/hakim-${data.coder_parameter.image_variant.value}_${local.selected_template_tag}.tar"
  )

  container_agent_bootstrap = local.workspace_agent_count > 0 ? base64encode("${data.coder_workspace.me.access_url}|${coder_agent.main[0].token}") : ""
  container_runtime_env_sha = local.workspace_agent_count > 0 ? sha256("${sha256(jsonencode(local.combined_env))}:${local.container_agent_bootstrap}") : sha256(jsonencode(local.combined_env))
  container_environment_variables = local.workspace_agent_count > 0 ? merge(local.combined_env, {
    CODER_AGENT_BOOTSTRAP = local.container_agent_bootstrap
    CODER_RUNTIME_ENV_SHA = local.container_runtime_env_sha
  }) : local.combined_env
  container_runtime_env_b64 = join(",", [for key in sort(keys(local.combined_env)) : "${key}=${base64encode(tostring(local.combined_env[key]))}"])

  home_disk_enabled          = data.coder_parameter.enable_home_disk.value
  home_volume_id             = length(data.coder_parameter.proxmox_home_volume_id) > 0 ? trimspace(data.coder_parameter.proxmox_home_volume_id[0].value) : ""
  home_datastore_id          = length(data.coder_parameter.proxmox_home_datastore_id) > 0 && trimspace(data.coder_parameter.proxmox_home_datastore_id[0].value) != "" ? trimspace(data.coder_parameter.proxmox_home_datastore_id[0].value) : "local-lvm"
  home_migration_mode        = length(data.coder_parameter.home_migration_mode) > 0 ? data.coder_parameter.home_migration_mode[0].value : "copy_keep_source"
  home_owner_slug            = replace(replace(replace(lower(trimspace(data.coder_workspace_owner.me.name)), "/", "-"), " ", "-"), ":", "-")
  home_workspace_slug        = replace(replace(replace(lower(trimspace(data.coder_workspace.me.name)), "/", "-"), " ", "-"), ":", "-")
  home_mount_is_bind         = local.home_disk_enabled && startswith(local.home_volume_id, "/")
  home_requires_root_session = false
  home_hook_version          = "2026-06-25.1"
  home_hook_spec             = local.home_disk_enabled ? "hakim_home=enabled,datastore=${base64encode(local.home_datastore_id)},owner=${local.home_owner_slug},workspace=${local.home_workspace_slug},size=${data.coder_parameter.home_disk_gb[0].value},volume=${base64encode(local.home_volume_id)},migration=${local.home_migration_mode},hook_version=${local.home_hook_version}" : ""

  docker_data_offload_enabled  = data.coder_parameter.enable_docker_data_offload.value
  docker_volume_id             = length(data.coder_parameter.proxmox_docker_volume_id) > 0 ? trimspace(data.coder_parameter.proxmox_docker_volume_id[0].value) : ""
  use_existing_docker_volume   = local.docker_volume_id != ""
  docker_bind_mount_enabled    = local.docker_data_offload_enabled && !local.use_existing_docker_volume
  docker_bind_path             = "/tank/hakim-docker/${local.home_owner_slug}/${local.home_workspace_slug}"
  docker_mount_source          = local.docker_data_offload_enabled ? (local.use_existing_docker_volume ? local.docker_volume_id : local.docker_bind_path) : ""
  docker_mount_is_bind         = local.docker_data_offload_enabled && startswith(local.docker_mount_source, "/")
  docker_requires_root_session = local.docker_data_offload_enabled && local.docker_mount_is_bind

  requires_root_session   = local.home_requires_root_session || local.docker_requires_root_session
  bind_mount_hook_enabled = local.home_disk_enabled || local.docker_bind_mount_enabled

  project_dir         = length(module.git-clone) > 0 ? module.git-clone[0].repo_dir : "/home/coder/project"
  git_setup_script    = file("${path.module}/scripts/setup-git.sh")
  tmux_sessions_raw   = length(data.coder_parameter.tmux_sessions) > 0 ? data.coder_parameter.tmux_sessions[0].value : "default"
  tmux_sessions_clean = [for session in split(",", local.tmux_sessions_raw) : trimspace(session) if trimspace(session) != ""]
  tmux_sessions       = length(local.tmux_sessions_clean) > 0 ? local.tmux_sessions_clean : ["default"]
  tmux_default_config = trimspace(file("${path.module}/tmux.conf"))
  tmux_config         = length(data.coder_parameter.tmux_config) > 0 && trimspace(data.coder_parameter.tmux_config[0].value) != "" ? trimspace(data.coder_parameter.tmux_config[0].value) : local.tmux_default_config
}

resource "coder_agent" "main" {
  count = local.workspace_agent_count

  arch = data.coder_provisioner.me.arch
  os   = "linux"
  env  = local.combined_env

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    sudo mkdir -p /dev/shm
    if ! grep -qsE '^[^ ]+ /dev/shm tmpfs ' /proc/mounts; then
      sudo mount -t tmpfs -o rw,nosuid,nodev,noexec,relatime,size=1g,mode=1777 tmpfs /dev/shm || true
    fi
    sudo chmod 1777 /dev/shm || true

    mkdir -p ~/.config/mise
    mkdir -p ~/.config
    mkdir -p ~/.local/bin
    mkdir -p ~/project
    touch ~/.config/mise/config.toml
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
    fi

    sed -i '/^export PATH="\$HOME\/\.local\/bin:\$PATH"$/d' ~/.bashrc ~/.profile 2>/dev/null || true
    sed -i '/^alias vim=nvim$/d' ~/.bashrc 2>/dev/null || true

    if ! grep -Fq 'if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then' ~/.bashrc; then
      cat >> ~/.bashrc <<'EOF'
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
EOF
    fi

    if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' ~/.profile; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.profile
    fi

    printf '\nalias vim=nvim\n' >> ~/.bashrc

    lazyvim_seed_src="/opt/hakim/lazyvim/nvim"
    lazyvim_seed_lock="$HOME/.local/share/hakim/lazyvim.seeded"
    nvim_health_log="$HOME/.local/share/hakim/nvim-health.log"
    mkdir -p "$HOME/.local/share/hakim"
    if [ -d "$lazyvim_seed_src" ] && [ ! -e "$HOME/.config/nvim/lua/config/lazy.lua" ] && [ ! -f "$lazyvim_seed_lock" ]; then
      rm -rf "$HOME/.config/nvim"
      cp -rT "$lazyvim_seed_src" "$HOME/.config/nvim"
      touch "$lazyvim_seed_lock"
    fi
    if [ -e "$HOME/.config/nvim/lua/config/lazy.lua" ] && [ ! -f "$lazyvim_seed_lock" ]; then
      touch "$lazyvim_seed_lock"
    fi
    if command -v timeout >/dev/null 2>&1; then
      timeout 60 nvim --headless "+checkhealth" +qa >"$nvim_health_log" 2>&1 || true
    else
      nvim --headless "+checkhealth" +qa >"$nvim_health_log" 2>&1 || true
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

resource "terraform_data" "workspace_rebuild_generation" {
  input = data.coder_parameter.workspace_rebuild_generation.value

  triggers_replace = [
    data.coder_parameter.workspace_rebuild_generation.value
  ]
}

resource "terraform_data" "proxmox_hook_script" {
  count = local.bind_mount_hook_enabled ? 1 : 0

  triggers_replace = {
    node_name     = data.coder_parameter.proxmox_node_name.value
    hookscript_id = data.coder_parameter.proxmox_home_bind_hook_script_id[0].value
    script_sha    = filesha256("${path.module}/scripts/hakim-home-bind-hook.sh")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/ensure-proxmox-hook.sh"

    environment = {
      PVE_ENDPOINT          = trimsuffix(data.coder_parameter.proxmox_endpoint.value, "/")
      PVE_NODE_NAME         = data.coder_parameter.proxmox_node_name.value
      PVE_USERNAME          = data.coder_parameter.proxmox_username.value
      PVE_PASSWORD          = data.coder_parameter.proxmox_password.value
      PVE_INSECURE          = tostring(data.coder_parameter.proxmox_insecure.value)
      PVE_HOOKSCRIPT_ID     = data.coder_parameter.proxmox_home_bind_hook_script_id[0].value
      PVE_HOOKSCRIPT_SOURCE = "${path.module}/scripts/hakim-home-bind-hook.sh"
    }
  }
}

resource "proxmox_virtual_environment_container" "workspace" {
  hook_script_file_id   = null
  node_name             = data.coder_parameter.proxmox_node_name.value
  vm_id                 = data.coder_parameter.proxmox_vm_id.value > 0 ? data.coder_parameter.proxmox_vm_id.value : null
  pool_id               = trimspace(data.coder_parameter.proxmox_pool_id.value) != "" ? data.coder_parameter.proxmox_pool_id.value : null
  description           = trimspace("Coder workspace ${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name} [${data.coder_workspace.me.transition}] ${local.home_hook_spec}")
  unprivileged          = true
  started               = data.coder_workspace.me.transition == "start"
  start_on_boot         = false
  tags                  = ["coder", "hakim", data.coder_parameter.image_variant.value, data.coder_parameter.egress_mode.value, "template-${local.selected_template_tag}"]
  environment_variables = local.container_environment_variables

  lifecycle {
    ignore_changes = [environment_variables, console, mount_point, hook_script_file_id]

    replace_triggered_by = [terraform_data.workspace_rebuild_generation]

    precondition {
      condition     = !local.requires_root_session || (trimspace(data.coder_parameter.proxmox_username.value) == "root@pam" && trimspace(data.coder_parameter.proxmox_password.value) != "")
      error_message = "Bind-mounted home/docker paths require root@pam session auth. Set proxmox_username=root@pam and provide proxmox_password."
    }

    precondition {
      condition     = data.coder_parameter.image_variant.value != "custom" || trimspace(data.coder_parameter.custom_template_file_id[0].value) != ""
      error_message = "custom_template_file_id must be set when image_variant is custom."
    }

    precondition {
      condition     = !local.bind_mount_hook_enabled || trimspace(data.coder_parameter.proxmox_home_bind_hook_script_id[0].value) != ""
      error_message = "Set proxmox_home_bind_hook_script_id to a valid Proxmox hookscript volume id when using auto bind persistence."
    }

  }
  cpu {
    cores = data.coder_parameter.container_cores.value
  }

  memory {
    dedicated = data.coder_parameter.container_memory_mb.value
    swap      = local.container_swap_mb
  }

  disk {
    datastore_id = data.coder_parameter.proxmox_container_datastore_id.value
    size         = data.coder_parameter.container_disk_gb.value
  }

  operating_system {
    template_file_id = local.selected_template_file_id
    type             = data.coder_parameter.image_variant.value == "custom" ? "unmanaged" : "debian"
  }

  features {
    fuse    = true
    keyctl  = true
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

  depends_on = [terraform_data.proxmox_hook_script]
}

resource "terraform_data" "home_volume_attach" {
  count = local.bind_mount_hook_enabled ? 1 : 0

  triggers_replace = {
    node_name      = data.coder_parameter.proxmox_node_name.value
    vm_id          = tostring(proxmox_virtual_environment_container.workspace.vm_id)
    owner_slug     = local.home_owner_slug
    workspace_slug = local.home_workspace_slug
    datastore_id   = local.home_datastore_id
    home_volume_id = local.home_volume_id
    size_gb        = length(data.coder_parameter.home_disk_gb) > 0 ? tostring(data.coder_parameter.home_disk_gb[0].value) : "0"
    migration_mode = local.home_migration_mode
    hookscript_id  = data.coder_parameter.proxmox_home_bind_hook_script_id[0].value
    transition     = data.coder_workspace.me.transition
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/ensure-proxmox-hook.sh"

    environment = {
      PVE_ENDPOINT          = trimsuffix(data.coder_parameter.proxmox_endpoint.value, "/")
      PVE_NODE_NAME         = data.coder_parameter.proxmox_node_name.value
      PVE_VM_ID             = tostring(proxmox_virtual_environment_container.workspace.vm_id)
      PVE_USERNAME          = data.coder_parameter.proxmox_username.value
      PVE_PASSWORD          = data.coder_parameter.proxmox_password.value
      PVE_INSECURE          = tostring(data.coder_parameter.proxmox_insecure.value)
      PVE_HOOKSCRIPT_ID     = data.coder_parameter.proxmox_home_bind_hook_script_id[0].value
      PVE_HOOKSCRIPT_SOURCE = "${path.module}/scripts/hakim-home-bind-hook.sh"
    }
  }

  depends_on = [proxmox_virtual_environment_container.workspace]
}

resource "terraform_data" "workspace_agent_env" {
  count = local.workspace_agent_count

  triggers_replace = {
    node_name       = data.coder_parameter.proxmox_node_name.value
    vm_id           = tostring(proxmox_virtual_environment_container.workspace.vm_id)
    endpoint        = trimsuffix(data.coder_parameter.proxmox_endpoint.value, "/")
    insecure        = tostring(data.coder_parameter.proxmox_insecure.value)
    agent_token_sha = sha256(coder_agent.main[0].token)
    env_sha         = local.container_runtime_env_sha
    home_attached   = tostring(local.home_disk_enabled)
    docker_source   = local.docker_mount_is_bind ? local.docker_mount_source : ""
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/bootstrap-agent-env.sh"

    environment = {
      PVE_ENDPOINT       = trimsuffix(data.coder_parameter.proxmox_endpoint.value, "/")
      PVE_NODE_NAME      = data.coder_parameter.proxmox_node_name.value
      PVE_VM_ID          = tostring(proxmox_virtual_environment_container.workspace.vm_id)
      PVE_API_TOKEN      = data.coder_parameter.proxmox_api_token.value
      PVE_USERNAME       = local.requires_root_session ? data.coder_parameter.proxmox_username.value : ""
      PVE_PASSWORD       = local.requires_root_session ? data.coder_parameter.proxmox_password.value : ""
      PVE_INSECURE       = tostring(data.coder_parameter.proxmox_insecure.value)
      CT_AGENT_BOOTSTRAP = local.container_agent_bootstrap
      CT_RUNTIME_ENV_B64 = local.container_runtime_env_b64
      CT_RUNTIME_ENV_SHA = local.container_runtime_env_sha
      PVE_HOME_SOURCE    = ""
      PVE_DOCKER_SOURCE  = local.docker_mount_is_bind ? local.docker_mount_source : ""
    }
  }

  depends_on = [proxmox_virtual_environment_container.workspace]
}

module "shekohex_agent" {
  count     = local.workspace_agent_count
  source    = "github.com/shekohex/hakim//coder/modules/shekohex-agent?ref=main"
  agent_id  = coder_agent.main[0].id
  auth_json = data.coder_parameter.shekohex_agent_auth.value
}

module "openclaw_node" {
  count = (
    local.workspace_agent_count > 0 &&
    data.coder_parameter.enable_openclaw_node.value &&
    contains(["php", "dotnet", "js", "rust", "android", "elixir"], data.coder_parameter.image_variant.value) &&
    length(data.coder_parameter.openclaw_bridge_host) > 0 &&
    trimspace(data.coder_parameter.openclaw_bridge_host[0].value) != ""
  ) ? 1 : 0

  source                 = "github.com/shekohex/hakim//coder/modules/openclaw-node?ref=main"
  agent_id               = coder_agent.main[0].id
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
  order = 997
}

resource "coder_script" "git_setup" {
  count        = local.workspace_agent_count
  agent_id     = coder_agent.main[0].id
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
  count      = local.workspace_agent_count > 0 && data.coder_parameter.git_url.value != "" ? 1 : 0
  source     = "registry.coder.com/coder/git-clone/coder"
  agent_id   = coder_agent.main[0].id
  url        = data.coder_parameter.git_url.value
  base_dir   = "/home/coder"
  depends_on = [coder_script.git_setup]
}

module "dotfiles" {
  count    = local.workspace_agent_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  agent_id = coder_agent.main[0].id
}

module "coder-login" {
  count    = data.coder_parameter.enable_coder_login.value ? local.workspace_agent_count : 0
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main[0].id
}

module "git-commit-signing" {
  count      = data.coder_parameter.enable_git_commit_signing.value ? local.workspace_agent_count : 0
  source     = "github.com/shekohex/hakim//coder/modules/git-commit-signing?ref=main"
  agent_id   = coder_agent.main[0].id
  depends_on = [coder_script.git_setup]
}

module "ssh-keys" {
  count      = data.coder_parameter.enable_ssh_keys.value ? local.workspace_agent_count : 0
  source     = "github.com/shekohex/hakim//coder/modules/ssh-keys?ref=main"
  agent_id   = coder_agent.main[0].id
  depends_on = [coder_script.git_setup]
}

module "zed" {
  count    = data.coder_parameter.enable_zed.value ? local.workspace_agent_count : 0
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.4"
  agent_id = coder_agent.main[0].id
  folder   = local.project_dir
  order    = 0
}

module "tmux" {
  count       = data.coder_parameter.enable_tmux.value ? local.workspace_agent_count : 0
  source      = "registry.coder.com/anomaly/tmux/coder"
  version     = "1.0.4"
  agent_id    = coder_agent.main[0].id
  sessions    = local.tmux_sessions
  tmux_config = local.tmux_config
}

module "et" {
  count    = data.coder_parameter.enable_et.value ? local.workspace_agent_count : 0
  source   = "github.com/shekohex/hakim//coder/modules/et?ref=main"
  agent_id = coder_agent.main[0].id
}

module "vault" {
  count                = data.coder_parameter.enable_vault.value ? local.workspace_agent_count : 0
  source               = "registry.coder.com/modules/vault-github/coder"
  version              = "1.0.7"
  agent_id             = coder_agent.main[0].id
  vault_addr           = data.coder_parameter.vault_addr[count.index].value
  coder_github_auth_id = data.coder_parameter.vault_github_auth_id[count.index].value
}

module "code-server" {
  count          = local.workspace_agent_count
  folder         = local.project_dir
  source         = "registry.coder.com/coder/code-server/coder"
  version        = "~> 1.0"
  agent_id       = coder_agent.main[0].id
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

data "coder_workspace_preset" "android_quick" {
  name        = "Android Quick Start"
  description = "Android SDK + NDK + Java environment"
  icon        = "https://cdn.simpleicons.org/android?viewbox=auto"
  parameters = {
    "image_variant" = "android"
    "git_url"       = ""
    "system_prompt" = "You are working on a modern Android app. Use Gradle, adb, and Android SDK/NDK tooling."
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
  count        = local.workspace_agent_count
  agent_id     = coder_agent.main[0].id
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
