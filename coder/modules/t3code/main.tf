terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

locals {
  app_slug       = "t3"
  icon           = "https://t3.codes/apple-touch-icon.png"
  port           = 1337
  install_script = file("${path.module}/scripts/install.sh")
  update_script  = file("${path.module}/scripts/update.sh")
}

resource "coder_script" "t3code_install" {
  agent_id     = var.agent_id
  display_name = "Install T3 Code"
  icon         = local.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/t3code-install-$$.sh"
    UPDATE_SCRIPT="/tmp/t3code-update-$$.sh"

    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    echo -n '${base64encode(local.update_script)}' | base64 -d > "$UPDATE_SCRIPT"
    chmod +x "$UPDATE_SCRIPT"

    ARG_UPDATE_SCRIPT="$UPDATE_SCRIPT" bash "$INSTALL_SCRIPT"

    rm -f "$INSTALL_SCRIPT" "$UPDATE_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_app" "t3" {
  slug         = local.app_slug
  display_name = "T3 Code"
  agent_id     = var.agent_id
  url          = "http://localhost:${local.port}/"
  icon         = local.icon
  share        = "public"
  subdomain    = true

  healthcheck {
    url       = "http://localhost:${local.port}/"
    interval  = 5
    threshold = 30
  }
}

output "app_id" {
  value = coder_app.t3.id
}
