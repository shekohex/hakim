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
    name  = "Base (Minimal)"
    value = "base"
    icon  = "/icon/debian.svg"
  }
  option {
    name  = "PHP 8.3"
    value = "php"
    icon  = "/icon/php.svg"
  }
  option {
    name  = "DotNet 8"
    value = "dotnet"
    icon  = "/icon/dotnet.svg"
  }
}

data "coder_parameter" "git_url" {
  name         = "git_url"
  display_name = "Git Repository URL"
  default      = ""
  type         = "string"
  description  = "Optional: Auto-clone a repository on startup."
  icon         = "/icon/git.svg"
}

data "coder_parameter" "opencode_auth" {
  name         = "opencode_auth"
  display_name = "OpenCode Auth JSON"
  description  = "Paste content of ~/.local/share/opencode/auth.json"
  form_type    = "textarea"
  type         = "string"
  default      = "{}"
  mutable      = true
  icon         = "/icon/lock.svg"
}

data "coder_parameter" "opencode_config" {
  name         = "opencode_config"
  display_name = "OpenCode Config JSON"
  description  = "OpenCode JSON config. https://opencode.ai/docs/config/"
  type         = "string"
  form_type    = "textarea"
  default      = "{}"
  mutable      = true
  icon         = "/icon/lock.svg"
}

data "coder_parameter" "system_prompt" {
  name         = "system_prompt"
  display_name = "System Prompt"
  type         = "string"
  form_type    = "textarea"
  description  = "System prompt for the AI agent."
  default      = ""
  mutable      = true
  icon         = "/icon/robot.svg"
}


# ------------------------------------------------------------------------------
# Agent & AI Task
# ------------------------------------------------------------------------------

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
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
  source        = "registry.coder.com/coder-labs/opencode/coder"
  version       = "0.1.1"
  agent_id      = coder_agent.main.id
  workdir       = "/home/coder/project"
  auth_json     = data.coder_parameter.opencode_auth.value
  config_json   = data.coder_parameter.opencode_config.value
  order         = 999
  cli_app       = true
  report_tasks  = true
  ai_prompt     = data.coder_task.me.prompt
  system_prompt = data.coder_parameter.system_prompt.value
}

module "git-clone" {
  count    = data.coder_parameter.git_url.value != "" ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_url.value
}

module "dotfiles" {
  source   = "registry.coder.com/coder/dotfiles/coder"
  agent_id = coder_agent.main.id
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  folder   = "/home/coder/project"
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
  settings = {
    "workbench.colorTheme" : "Default Dark Modern"
  }
}

module "windsurf" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windsurf/coder"
  version  = "1.2.0"
  agent_id = coder_agent.main.id
}

# ------------------------------------------------------------------------------
# Infrastructure (Docker)
# ------------------------------------------------------------------------------

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
  image = "ghcr.io/shekohex/hakim-${data.coder_parameter.image_variant.value}:latest"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
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

