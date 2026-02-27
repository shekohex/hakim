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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "https://raw.githubusercontent.com/openclaw/openclaw/refs/heads/main/docs/assets/pixel-lobster.svg"
}

variable "install_openclaw" {
  type        = bool
  description = "Whether to install OpenClaw via npm."
  default     = true
}

variable "openclaw_version" {
  type        = string
  description = "The version of OpenClaw to install."
  # VERSION_UPDATE_BEGIN: openclaw
  default     = "2026.2.26"
  # VERSION_UPDATE_END: openclaw
}

variable "bridge_host" {
  type        = string
  description = "Gateway bridge host to connect the node host to."
  default     = ""
}

variable "bridge_port" {
  type        = number
  description = "Gateway bridge port to connect the node host to."
  default     = 18790
}

variable "bridge_tls" {
  type        = bool
  description = "Whether to use TLS for the bridge connection."
  default     = false
}

variable "bridge_tls_fingerprint" {
  type        = string
  description = "SHA256 TLS certificate fingerprint to pin when bridge TLS is enabled."
  default     = ""
}

variable "display_name" {
  type        = string
  description = "Node display name shown on the gateway."
  default     = ""
}

variable "gateway_ws_url" {
  type        = string
  description = "Optional Gateway WebSocket URL for auto-approving pairing (e.g., ws://host:18789 or wss://...)."
  default     = ""
}

variable "gateway_token" {
  type        = string
  description = "Optional Gateway token for auto-approving pairing."
  default     = ""
}

variable "auto_approve_pairing" {
  type        = bool
  description = "Whether to attempt to auto-approve the node pairing via gateway RPC."
  default     = false
}

locals {
  app_slug       = "openclaw-node"
  install_script = file("${path.module}/scripts/install.sh")
  start_script   = file("${path.module}/scripts/start.sh")
}

resource "coder_script" "openclaw_install" {
  agent_id     = var.agent_id
  display_name = "Install OpenClaw"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/openclaw-install-$$.sh"
    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_INSTALL_OPENCLAW='${var.install_openclaw}' \
    ARG_OPENCLAW_VERSION='${var.openclaw_version}' \
    "$INSTALL_SCRIPT"

    rm -f "$INSTALL_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_script" "openclaw_node_start" {
  agent_id     = var.agent_id
  display_name = "Start OpenClaw Node Host"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    START_SCRIPT="/tmp/openclaw-node-start-$$.sh"
    echo -n '${base64encode(local.start_script)}' | base64 -d > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"

    ARG_BRIDGE_HOST='${var.bridge_host}' \
    ARG_BRIDGE_PORT='${var.bridge_port}' \
    ARG_BRIDGE_TLS='${var.bridge_tls}' \
    ARG_BRIDGE_TLS_FINGERPRINT='${var.bridge_tls_fingerprint != null ? base64encode(replace(var.bridge_tls_fingerprint, "'", "'\\''")) : ""}' \
    ARG_DISPLAY_NAME='${var.display_name != null ? base64encode(replace(var.display_name, "'", "'\\''")) : ""}' \
    ARG_GATEWAY_WS_URL='${var.gateway_ws_url}' \
    ARG_GATEWAY_TOKEN='${var.gateway_token != null ? base64encode(replace(var.gateway_token, "'", "'\\''")) : ""}' \
    ARG_AUTO_APPROVE_PAIRING='${var.auto_approve_pairing}' \
    "$START_SCRIPT"

    rm -f "$START_SCRIPT"
  EOT
  run_on_start = true
  depends_on   = [coder_script.openclaw_install]
}
