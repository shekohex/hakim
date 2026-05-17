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

variable "icon" {
  type        = string
  description = "The icon to use for the install script."
  default     = "/icon/terminal.svg"
}

variable "auth_json" {
  type        = string
  description = "Pi auth.json written to ~/.pi/agent/auth.json."
  default     = "{}"
  sensitive   = true
}

variable "install_shekohex_agent" {
  type        = bool
  description = "Whether to install Shekohex Agent."
  default     = true
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Shekohex Agent."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Shekohex Agent."
  default     = null
}

locals {
  install_script = file("${path.module}/scripts/install.sh")
}

resource "coder_script" "shekohex_agent_install" {
  agent_id     = var.agent_id
  display_name = "Install Shekohex Agent"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/shekohex-agent-install-$$.sh"

    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_AUTH_JSON='${base64encode(replace(var.auth_json, "'", "'\\''"))}' \
    ARG_INSTALL_SHEKOHEX_AGENT='${var.install_shekohex_agent}' \
    ARG_PRE_INSTALL_SCRIPT='${var.pre_install_script != null ? base64encode(var.pre_install_script) : ""}' \
    ARG_POST_INSTALL_SCRIPT='${var.post_install_script != null ? base64encode(var.post_install_script) : ""}' \
    bash -lc "$INSTALL_SCRIPT"

    rm -f "$INSTALL_SCRIPT"
  EOT
  run_on_start = true
}
