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

variable "enabled" {
  type        = bool
  description = "Whether to install and run Paseo."
  default     = true
}

locals {
  app_slug       = "paseo"
  icon           = "https://app.paseo.sh/apple-touch-icon.png"
  port           = 6767
  install_script = file("${path.module}/scripts/install.sh")
}

resource "coder_script" "paseo_install" {
  agent_id     = var.agent_id
  display_name = "Configure Paseo"
  icon         = local.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/paseo-install-$$.sh"

    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_ENABLED='${var.enabled}' bash "$INSTALL_SCRIPT"

    rm -f "$INSTALL_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_app" "paseo" {
  count = var.enabled ? 1 : 0

  slug         = local.app_slug
  display_name = "Paseo"
  agent_id     = var.agent_id
  url          = "http://localhost:${local.port}/"
  icon         = local.icon
  share        = "owner"
  subdomain    = true

  healthcheck {
    url       = "http://localhost:${local.port}/"
    interval  = 5
    threshold = 30
  }
}

output "app_id" {
  value = var.enabled ? coder_app.paseo[0].id : null
}
