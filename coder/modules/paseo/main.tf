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
  default     = "https://app.paseo.sh/favicon.ico"
}

variable "workdir" {
  type        = string
  description = "The folder to run Paseo in."
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Paseo"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Paseo."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Paseo."
  default     = null
}

variable "install_paseo" {
  type        = bool
  description = "Whether to install Paseo."
  default     = true
}

variable "paseo_version" {
  type        = string
  description = "The version of Paseo to install."
  default     = "latest"
}

variable "paseo_tarball_url" {
  type        = string
  description = "Optional tarball URL for a built Paseo CLI package. When set, this overrides paseo_version."
  default     = ""
}

variable "paseo_home_dir" {
  type        = string
  description = "Custom Paseo home directory. Supports ~ expansion."
  default     = "~/.paseo"
}

variable "config_json" {
  type        = string
  description = "Paseo JSON config written to ~/.paseo/config.json before daemon start."
  default     = <<-EOT
{
  "version": 1,
  "daemon": {
    "listen": "127.0.0.1:6767",
    "cors": {
      "allowedOrigins": [
        "https://app.paseo.sh",
        "https://paseo.0iq.xyz"
      ]
    },
    "relay": {
      "enabled": true
    }
  },
  "app": {
    "baseUrl": "https://paseo.0iq.xyz"
  },
  "features": {
    "dictation": {
      "enabled": false
    },
    "voiceMode": {
      "enabled": false
    }
  },
  "log": {
    "level": "debug",
    "format": "json"
  }
}
EOT
}

locals {
  app_slug       = "paseo"
  install_script = file("${path.module}/scripts/install.sh")
  start_script   = file("${path.module}/scripts/start.sh")
  parsed_config  = try(jsondecode(var.config_json), {})
  web_app_url    = try(local.parsed_config.app.baseUrl, "https://app.paseo.sh")
}

resource "coder_script" "paseo_start" {
  agent_id     = var.agent_id
  display_name = "Install Paseo Daemon"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    INSTALL_SCRIPT="/tmp/paseo-install-$$.sh"
    START_SCRIPT="/tmp/paseo-start-$$.sh"

    echo -n '${base64encode(local.install_script)}' | base64 -d > "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"

    ARG_PASEO_VERSION='${var.paseo_version}' \
    ARG_PASEO_TARBALL_URL='${base64encode(var.paseo_tarball_url)}' \
    ARG_INSTALL_PASEO='${var.install_paseo}' \
    ARG_PRE_INSTALL_SCRIPT='${var.pre_install_script != null ? base64encode(var.pre_install_script) : ""}' \
    ARG_POST_INSTALL_SCRIPT='${var.post_install_script != null ? base64encode(var.post_install_script) : ""}' \
    bash -lc "$INSTALL_SCRIPT"

    echo -n '${base64encode(local.start_script)}' | base64 -d > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"

    ARG_PASEO_HOME_DIR='${base64encode(var.paseo_home_dir)}' \
    ARG_PASEO_CONFIG='${var.config_json != null ? base64encode(replace(var.config_json, "'", "'\\''")) : ""}' \
    bash -lc "$START_SCRIPT"

    rm -f "$INSTALL_SCRIPT" "$START_SCRIPT"
  EOT
  run_on_start = true
}

resource "coder_app" "paseo_web" {
  slug         = local.app_slug
  display_name = var.web_app_display_name
  agent_id     = var.agent_id
  url          = local.web_app_url
  icon         = var.icon
  order        = var.order
  group        = var.group
}

output "app_id" {
  value = coder_app.paseo_web.id
}
