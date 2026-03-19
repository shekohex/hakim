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
  default     = "https://app.happy.engineering/favicon.ico"
}

variable "workdir" {
  type        = string
  description = "The folder to run Happy in."
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Happy"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Happy."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Happy."
  default     = null
}

variable "install_happy_coder" {
  type        = bool
  description = "Whether to install Happy."
  default     = true
}

variable "happy_coder_version" {
  type        = string
  description = "The npm version or dist-tag of happy-coder to install."
  # VERSION_UPDATE_BEGIN: happy-coder
  default = "0.15.0-beta.0"
  # VERSION_UPDATE_END: happy-coder
}

variable "happy_server_url" {
  type        = string
  description = "Custom Happy server URL."
  default     = "https://api.cluster-fluster.com"
}

variable "happy_webapp_url" {
  type        = string
  description = "Custom Happy web app URL."
  default     = "https://app.happy.engineering"
}

variable "happy_home_dir" {
  type        = string
  description = "Custom Happy home directory. Supports ~ expansion."
  default     = "~/.happy"
}

variable "happy_disable_caffeinate" {
  type        = bool
  description = "Disable Happy macOS sleep prevention."
  default     = false
}

variable "happy_experimental" {
  type        = bool
  description = "Enable Happy experimental features."
  default     = false
}

variable "opencode_port" {
  type        = number
  description = "Port of the OpenCode server Happy should attach to via ACP."
  default     = 4096
}

locals {
  workdir        = trimsuffix(var.workdir, "/")
  app_slug       = "happy-coder"
  install_script = file("${path.module}/scripts/install.sh")
  start_script   = file("${path.module}/scripts/start.sh")
}

resource "coder_script" "happy_coder_start" {
  agent_id     = var.agent_id
  display_name = "Start Happy ACP Session"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/happy-coder-install-$$.sh"
    START_SCRIPT="/tmp/happy-coder-start-$$.sh"

    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_HAPPY_CODER_VERSION='${var.happy_coder_version}' \
    ARG_INSTALL_HAPPY_CODER='${var.install_happy_coder}' \
    ARG_PRE_INSTALL_SCRIPT='${var.pre_install_script != null ? base64encode(var.pre_install_script) : ""}' \
    ARG_POST_INSTALL_SCRIPT='${var.post_install_script != null ? base64encode(var.post_install_script) : ""}' \
    bash -lc "$INSTALL_SCRIPT"

    echo -n '${base64encode(local.start_script)}' | base64 -d > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"

    ARG_WORKDIR='${local.workdir}' \
    ARG_OPENCODE_PORT='${var.opencode_port}' \
    ARG_HAPPY_SERVER_URL='${base64encode(var.happy_server_url)}' \
    ARG_HAPPY_WEBAPP_URL='${base64encode(var.happy_webapp_url)}' \
    ARG_HAPPY_HOME_DIR='${base64encode(var.happy_home_dir)}' \
    ARG_HAPPY_DISABLE_CAFFEINATE='${var.happy_disable_caffeinate}' \
    ARG_HAPPY_EXPERIMENTAL='${var.happy_experimental}' \
    bash -lc "$START_SCRIPT"

    rm -f "$INSTALL_SCRIPT" "$START_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_app" "happy_web" {
  slug         = local.app_slug
  display_name = var.web_app_display_name
  agent_id     = var.agent_id
  url          = var.happy_webapp_url
  icon         = var.icon
  order        = var.order
  group        = var.group
}

output "app_id" {
  value = coder_app.happy_web.id
}
