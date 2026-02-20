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
  description = "The icon to use for the startup script."
  default     = "/icon/terminal.svg"
}

variable "display_name" {
  type        = string
  description = "Display name for the startup script."
  default     = "Start ET + SSHD"
}

variable "et_port" {
  type        = number
  description = "Port for etserver."
  default     = 2022
}

variable "ssh_port" {
  type        = number
  description = "Port for internal sshd used by ET handshakes."
  default     = 2244
}

variable "bind_ip" {
  type        = string
  description = "Bind address for etserver and sshd."
  default     = "127.0.0.1"
}

variable "ssh_user" {
  type        = string
  description = "Allowed SSH user for internal sshd."
  default     = "coder"
}

locals {
  start_script = file("${path.module}/scripts/start.sh")
}

resource "coder_script" "et_start" {
  agent_id     = var.agent_id
  display_name = var.display_name
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    START_SCRIPT="/tmp/et-start-$$.sh"
    echo -n '${base64encode(local.start_script)}' | base64 -d > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"

    ARG_ET_PORT='${var.et_port}' \
    ARG_SSH_PORT='${var.ssh_port}' \
    ARG_BIND_IP='${var.bind_ip}' \
    ARG_SSH_USER='${var.ssh_user}' \
    "$START_SCRIPT"

    rm -f "$START_SCRIPT"
  EOT
  run_on_start = true
}
