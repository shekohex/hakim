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
  description = "Whether to install and run Avahi for mDNS hostname discovery."
  default     = true
}

resource "coder_script" "avahi" {
  agent_id     = var.agent_id
  display_name = "Configure mDNS"
  icon         = "/icon/network.svg"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail

    if [ '${var.enabled}' != 'true' ]; then
      if systemctl cat avahi-daemon.service > /dev/null 2>&1; then
        sudo systemctl disable --now avahi-daemon.service avahi-daemon.socket
      fi
      exit 0
    fi

    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y avahi-daemon
    sudo systemctl enable --now avahi-daemon.service
    sudo systemctl is-active --quiet avahi-daemon.service

    echo "mDNS available at $(hostname).local"
  EOT
}
