#!/bin/bash
set -euo pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

if command_exists bun; then
  export PATH="$HOME/.bun/bin:$PATH"
  GLOBAL_BIN_DIR=$(bun pm bin -g 2> /dev/null || true)
  if [ -n "$GLOBAL_BIN_DIR" ]; then
    export PATH="$GLOBAL_BIN_DIR:$PATH"
  fi
fi

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_OPENCODE_VERSION=${ARG_OPENCODE_VERSION:-latest}
ARG_INSTALL_OPENCODE=${ARG_INSTALL_OPENCODE:-true}
ARG_AUTH_JSON=$(echo -n "$ARG_AUTH_JSON" | base64 -d 2> /dev/null || echo "")
ARG_OPENCODE_CONFIG=$(echo -n "$ARG_OPENCODE_CONFIG" | base64 -d 2> /dev/null || echo "")
ARG_PRE_INSTALL_SCRIPT=$(echo -n "${ARG_PRE_INSTALL_SCRIPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_POST_INSTALL_SCRIPT=$(echo -n "${ARG_POST_INSTALL_SCRIPT:-}" | base64 -d 2> /dev/null || echo "")

printf "=== INSTALL CONFIG ===\n"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_MCP_APP_STATUS_SLUG: %s\n" "$ARG_MCP_APP_STATUS_SLUG"
printf "ARG_OPENCODE_VERSION: %s\n" "$ARG_OPENCODE_VERSION"
printf "ARG_INSTALL_OPENCODE: %s\n" "$ARG_INSTALL_OPENCODE"
if [ -n "$ARG_AUTH_JSON" ]; then
  printf "ARG_AUTH_JSON: [AUTH DATA RECEIVED]\n"
else
  printf "ARG_AUTH_JSON: [NOT PROVIDED]\n"
fi
if [ -n "$ARG_OPENCODE_CONFIG" ]; then
  printf "ARG_OPENCODE_CONFIG: [RECEIVED]\n"
else
  printf "ARG_OPENCODE_CONFIG: [NOT PROVIDED]\n"
fi
printf "==================================\n"

run_pre_install_script() {
  if [ -n "$ARG_PRE_INSTALL_SCRIPT" ]; then
    echo "Running pre-install script..."
    echo -n "$ARG_PRE_INSTALL_SCRIPT" > /tmp/pre_install.sh
    chmod +x /tmp/pre_install.sh
    /tmp/pre_install.sh 2>&1 | tee /tmp/pre_install.log
  fi
}

install_opencode() {
  if [ "$ARG_INSTALL_OPENCODE" = "true" ]; then
    if ! command_exists opencode; then
      echo "Installing OpenCode (version: ${ARG_OPENCODE_VERSION})..."
      if command_exists bun; then
        if [ "$ARG_OPENCODE_VERSION" = "latest" ]; then
          bun install -g opencode-ai
        else
          bun install -g "opencode-ai@${ARG_OPENCODE_VERSION}"
        fi

        GLOBAL_BIN_DIR=$(bun pm bin -g)
        if [ -n "$GLOBAL_BIN_DIR" ] && [ -f "$GLOBAL_BIN_DIR/opencode" ]; then
          export PATH="$GLOBAL_BIN_DIR:$PATH"
          if command_exists sudo; then
            echo "Symlinking opencode to /usr/local/bin"
            sudo ln -sf "$GLOBAL_BIN_DIR/opencode" /usr/local/bin/opencode
          fi
        fi
      else
        if [ "$ARG_OPENCODE_VERSION" = "latest" ]; then
          curl -fsSL https://opencode.ai/install | bash
        else
          VERSION=$ARG_OPENCODE_VERSION curl -fsSL https://opencode.ai/install | bash
        fi
        export PATH=/home/coder/.opencode/bin:$PATH
      fi

      if command_exists opencode; then
        echo "OpenCode installed successfully"
      else
        echo "ERROR: Failed to install OpenCode"
        exit 1
      fi
    else
      echo "OpenCode already installed"
    fi
  else
    echo "OpenCode installation skipped (ARG_INSTALL_OPENCODE=false)"
  fi
}

setup_opencode_config() {
  local opencode_config_file="$HOME/.config/opencode/opencode.json"
  local auth_json_file="$HOME/.local/share/opencode/auth.json"

  mkdir -p "$(dirname "$auth_json_file")"
  mkdir -p "$(dirname "$opencode_config_file")"

  setup_opencode_auth "$auth_json_file"

  if [ -n "$ARG_OPENCODE_CONFIG" ]; then
    echo "Writing to the config file"
    echo "$ARG_OPENCODE_CONFIG" > "$opencode_config_file"
  fi

  if [ "$ARG_REPORT_TASKS" = "true" ]; then
    setup_coder_mcp_server "$opencode_config_file"
  fi

  echo "MCP configuration completed: $opencode_config_file"
}

setup_opencode_auth() {
  local auth_json_file="$1"

  if [ -n "$ARG_AUTH_JSON" ]; then
    echo "$ARG_AUTH_JSON" > "$auth_json_file"
    printf "added auth json to %s" "$auth_json_file"
  else
    printf "auth json not provided"
  fi
}

setup_coder_mcp_server() {
  local opencode_config_file="$1"

  echo "Configuring OpenCode task reporting"
  export CODER_MCP_APP_STATUS_SLUG="$ARG_MCP_APP_STATUS_SLUG"
  echo "Coder integration configured for task reporting"

  echo "Adding Coder MCP server configuration"

  coder_config=$(
    cat << EOF
{
  "type": "local",
  "command": ["coder", "exp", "mcp", "server"],
  "enabled": true,
  "environment": {
    "CODER_MCP_APP_STATUS_SLUG": "${CODER_MCP_APP_STATUS_SLUG:-}",
    "CODER_AGENT_URL": "${CODER_AGENT_URL:-}",
    "CODER_AGENT_TOKEN": "${CODER_AGENT_TOKEN:-}",
    "CODER_MCP_ALLOWED_TOOLS": "coder_report_task"
  }
}
EOF
  )

  temp_file=$(mktemp)
  jq --argjson coder_config "$coder_config" '.mcp.coder = $coder_config' "$opencode_config_file" > "$temp_file"
  mv "$temp_file" "$opencode_config_file"
  echo "Coder MCP server configuration added"
}

run_post_install_script() {
  if [ -n "$ARG_POST_INSTALL_SCRIPT" ]; then
    echo "Running post-install script..."
    echo -n "$ARG_POST_INSTALL_SCRIPT" > /tmp/post_install.sh
    chmod +x /tmp/post_install.sh
    /tmp/post_install.sh 2>&1 | tee /tmp/post_install.log
  fi
}

run_pre_install_script
setup_opencode_config
install_opencode
run_post_install_script

echo "OpenCode module setup completed."
