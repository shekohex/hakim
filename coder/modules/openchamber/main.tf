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
  default     = "https://raw.githubusercontent.com/btriapitsyn/openchamber/refs/heads/main/docs/references/badges/openchamber-logo-dark.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run OpenChamber in."
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "OpenChamber"
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for the web app."
  default     = true
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing OpenChamber."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing OpenChamber."
  default     = null
}

variable "install_openchamber" {
  type        = bool
  description = "Whether to install OpenChamber."
  default     = true
}

variable "openchamber_version" {
  type        = string
  description = "The version of OpenChamber to install."
  # VERSION_UPDATE_BEGIN: openchamber
  default     = "1.6.2"
  # VERSION_UPDATE_END: openchamber
}

variable "port" {
  type        = number
  description = "The port for the OpenChamber web server."
  default     = 6904
}

variable "ui_password" {
  type        = string
  description = "Optional UI password for OpenChamber."
  default     = ""
}

locals {
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "openchamber"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".openchamber-module"
}

resource "coder_script" "openchamber_install" {
  agent_id     = var.agent_id
  display_name = "Install OpenChamber"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/openchamber-install-$$.sh"
    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_OPENCHAMBER_VERSION='${var.openchamber_version}' \
    ARG_INSTALL_OPENCHAMBER='${var.install_openchamber}' \
    ARG_PRE_INSTALL_SCRIPT='${var.pre_install_script != null ? base64encode(var.pre_install_script) : ""}' \
    ARG_POST_INSTALL_SCRIPT='${var.post_install_script != null ? base64encode(var.post_install_script) : ""}' \
    "$INSTALL_SCRIPT"
    
    rm -f "$INSTALL_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_script" "openchamber_start" {
  agent_id     = var.agent_id
  display_name = "Start OpenChamber Server"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    START_SCRIPT="/tmp/openchamber-start-$$.sh"
    echo -n '${base64encode(local.start_script)}' | base64 -d > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"

    ARG_WORKDIR='${local.workdir}' \
    ARG_PORT='${var.port}' \
    ARG_UI_PASSWORD='${var.ui_password != null ? base64encode(replace(var.ui_password, "'", "'\\''")) : ""}' \
    "$START_SCRIPT"
    
    rm -f "$START_SCRIPT"
  EOT
  run_on_start = true
  depends_on   = [coder_script.openchamber_install]
}

resource "coder_app" "openchamber_web" {
  slug         = local.app_slug
  display_name = var.web_app_display_name
  agent_id     = var.agent_id
  url          = "http://localhost:${var.port}/"
  icon         = var.icon
  order        = var.order
  group        = var.group
  subdomain    = var.subdomain

  healthcheck {
    url       = "http://localhost:${var.port}/"
    interval  = 5
    threshold = 30
  }
}

output "app_id" {
  value = coder_app.openchamber_web.id
}
