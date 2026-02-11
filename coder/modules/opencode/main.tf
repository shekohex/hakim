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
  default     = "/icon/opencode.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run OpenCode in."
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI via MCP"
  default     = true
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for OpenCode"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "OpenCode"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "OpenCode CLI"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing OpenCode."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing OpenCode."
  default     = null
}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for OpenCode."
  default     = ""
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for the web app."
  default     = true
}

variable "install_opencode" {
  type        = bool
  description = "Whether to install OpenCode."
  default     = true
}

variable "opencode_version" {
  type        = string
  description = "The version of OpenCode to install."
  # VERSION_UPDATE_BEGIN: opencode
  default     = "1.1.56"
  # VERSION_UPDATE_END: opencode
}

variable "continue" {
  type        = bool
  description = "continue the last session. Uses the --continue flag"
  default     = false
}

variable "session_id" {
  type        = string
  description = "Session id to continue. Passed via --session"
  default     = ""
}

variable "auth_json" {
  type        = string
  description = "Your auth.json from $HOME/.local/share/opencode/auth.json, Required for non-interactive authentication"
  default     = ""
}

variable "config_json" {
  type        = string
  description = "OpenCode JSON config. https://opencode.ai/docs/config/"
  default     = ""
}

variable "port" {
  type        = number
  description = "The port for the OpenCode web server."
  default     = 4096
}

variable "hostname" {
  type        = string
  description = "The hostname for the OpenCode web server."
  default     = "0.0.0.0"
}

locals {
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "opencode"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".opencode-module"
}

resource "coder_script" "opencode_start" {
  agent_id     = var.agent_id
  display_name = "Start OpenCode Server"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/opencode-install-$$.sh"
    START_SCRIPT="/tmp/opencode-start-$$.sh"

    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_OPENCODE_VERSION='${var.opencode_version}' \
    ARG_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_INSTALL_OPENCODE='${var.install_opencode}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_WORKDIR='${local.workdir}' \
    ARG_AUTH_JSON='${var.auth_json != null ? base64encode(replace(var.auth_json, "'", "'\\''")) : ""}' \
    ARG_OPENCODE_CONFIG='${var.config_json != null ? base64encode(replace(var.config_json, "'", "'\\''")) : ""}' \
    ARG_PRE_INSTALL_SCRIPT='${var.pre_install_script != null ? base64encode(var.pre_install_script) : ""}' \
    ARG_POST_INSTALL_SCRIPT='${var.post_install_script != null ? base64encode(var.post_install_script) : ""}' \
    bash -lc "$INSTALL_SCRIPT"

    echo -n '${base64encode(local.start_script)}' | base64 -d > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"

    ARG_WORKDIR='${local.workdir}' \
    ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
    ARG_SESSION_ID='${var.session_id}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_CONTINUE='${var.continue}' \
    ARG_PORT='${var.port}' \
    ARG_HOSTNAME='${var.hostname}' \
    bash -lc "$START_SCRIPT"

    rm -f "$INSTALL_SCRIPT" "$START_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_app" "opencode_web" {
  slug         = local.app_slug
  display_name = var.web_app_display_name
  agent_id     = var.agent_id
  url          = "http://localhost:${var.port}/"
  icon         = var.icon
  order        = var.order
  group        = var.group
  subdomain    = var.subdomain

  healthcheck {
    url       = "http://localhost:${var.port}/project/current"
    interval  = 5
    threshold = 30
  }
}

resource "coder_app" "opencode_cli" {
  count = var.cli_app ? 1 : 0

  slug         = "${local.app_slug}-cli"
  display_name = var.cli_app_display_name
  agent_id     = var.agent_id
  command      = "bash -lc \"opencode\""
  icon         = var.icon
  order        = var.order != null ? var.order + 1 : null
  group        = var.group
}

output "task_app_id" {
  value = coder_app.opencode_web.id
}
