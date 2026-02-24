#!/bin/bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$PATH:$HOME/.opencode/bin"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

resolve_bun_bin() {
  if [ -x "$HOME/.bun/bin/bun" ]; then
    printf '%s\n' "$HOME/.bun/bin/bun"
    return 0
  fi

  for candidate in \
    /usr/local/share/mise/installs/bun/*/bin/bun \
    "$HOME/.local/share/mise/installs/bun/*/bin/bun"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command_exists bun; then
    command -v bun
    return 0
  fi

  return 1
}

run_with_bun_lock() {
  if command_exists flock; then
    (
      exec 9>"/tmp/hakim-bun-global.lock"
      flock -w 600 9 || {
        echo "ERROR: timed out waiting for bun global lock"
        exit 1
      }
      "$@"
    )
    return
  fi

  local lock_dir="/tmp/hakim-bun-global.lock.d"
  local elapsed=0
  local timeout=600

  while ! mkdir "$lock_dir" 2> /dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "ERROR: timed out waiting for bun global lock"
      return 1
    fi
  done

  trap 'rmdir "$lock_dir" 2>/dev/null || true' RETURN
  "$@"
}

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
    BUN_BIN="$(resolve_bun_bin 2> /dev/null || true)"
    if [ -n "$BUN_BIN" ]; then
      export PATH="$(dirname "$BUN_BIN"):$PATH"
      if [ ! -x "$HOME/.bun/bin/opencode" ]; then
        echo "Installing OpenCode (version: ${ARG_OPENCODE_VERSION})..."
        if [ "$ARG_OPENCODE_VERSION" = "latest" ]; then
          run_with_bun_lock "$BUN_BIN" add -g opencode-ai
        else
          run_with_bun_lock "$BUN_BIN" add -g "opencode-ai@${ARG_OPENCODE_VERSION}"
        fi
      else
        echo "OpenCode already installed in bun global bin"
      fi
    else
      if ! command_exists opencode; then
        echo "Installing OpenCode (version: ${ARG_OPENCODE_VERSION})..."
        if [ "$ARG_OPENCODE_VERSION" = "latest" ]; then
          curl -fsSL https://opencode.ai/install | bash
        else
          VERSION=$ARG_OPENCODE_VERSION curl -fsSL https://opencode.ai/install | bash
        fi
        export PATH=/home/coder/.opencode/bin:$PATH
      else
        echo "OpenCode already installed"
      fi
    fi

    OPENCODE_BIN=""
    if [ -n "$BUN_BIN" ] && [ -x "$HOME/.bun/bin/opencode" ]; then
      OPENCODE_BIN="$HOME/.bun/bin/opencode"
    elif command_exists opencode; then
      OPENCODE_BIN=$(command -v opencode 2> /dev/null || true)
    fi

    if [ -n "$OPENCODE_BIN" ] && [ -f "$OPENCODE_BIN" ] && command_exists sudo; then
      echo "Symlinking opencode to /usr/local/bin"
      sudo ln -sf "$OPENCODE_BIN" /usr/local/bin/opencode
    fi

    if command_exists opencode; then
      echo "OpenCode installed successfully"
    else
      echo "ERROR: Failed to install OpenCode"
      exit 1
    fi
  else
    echo "OpenCode installation skipped (ARG_INSTALL_OPENCODE=false)"
  fi
}

setup_opencode_config() {
  local opencode_config_file="$HOME/.config/opencode/opencode.jsonc"
  local auth_json_file="$HOME/.local/share/opencode/auth.json"
  local plugin_dir="$HOME/.config/opencode/plugins"
  local plugin_file="$plugin_dir/hakim-host-attachments.ts"

  mkdir -p "$(dirname "$auth_json_file")"
  mkdir -p "$(dirname "$opencode_config_file")"
  mkdir -p "$plugin_dir"

  setup_opencode_auth "$auth_json_file"

  if [ -n "$ARG_OPENCODE_CONFIG" ]; then
    if [ -f "$opencode_config_file" ]; then
      echo "WARNING: $opencode_config_file already exists, skipping config write"
    else
      echo "Writing to the config file"
      echo "$ARG_OPENCODE_CONFIG" > "$opencode_config_file"
    fi
  fi

  if [ ! -f "$plugin_file" ]; then
    cat >"$plugin_file" <<'EOF'
import type { Plugin } from "@opencode-ai/plugin"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

type XferConfig = {
  url: string
  token?: string
  port?: number
}

function readConfig(): XferConfig | undefined {
  const file = path.join(os.homedir(), ".config", "opencode", "hakim-host-attachments.json")
  try {
    const raw = fs.readFileSync(file, "utf8")
    const cfg = JSON.parse(raw)
    if (!cfg || typeof cfg !== "object") return undefined
    if (typeof cfg.url !== "string" || cfg.url.length === 0) return undefined
    if ("token" in cfg && typeof cfg.token !== "string") return undefined
    return cfg as XferConfig
  } catch {
    return undefined
  }
}

function unescapeToken(token: string) {
  return token.replace(/\\([\\\s"'])/g, "$1")
}

function stripQuotes(token: string) {
  if (token.length >= 2) {
    const a = token[0]
    const b = token[token.length - 1]
    if ((a === "\"" && b === "\"") || (a === "'" && b === "'")) return token.slice(1, -1)
  }
  return token
}

function tokenize(input: string): { token: string; start: number; end: number }[] {
  const out: { token: string; start: number; end: number }[] = []
  let i = 0
  while (i < input.length) {
    while (i < input.length && /\s/.test(input[i]!)) i++
    if (i >= input.length) break
    const start = i
    let quote: "\"" | "'" | null = null
    let tok = ""
    while (i < input.length) {
      const ch = input[i]!
      if (!quote && /\s/.test(ch)) break
      if (!quote && (ch === "\"" || ch === "'")) {
        quote = ch
        tok += ch
        i++
        continue
      }
      if (quote && ch === quote) {
        quote = null
        tok += ch
        i++
        continue
      }
      if (ch === "\\" && i + 1 < input.length) {
        tok += ch + input[i + 1]!
        i += 2
        continue
      }
      tok += ch
      i++
    }
    const end = i
    out.push({ token: tok, start, end })
  }
  return out
}

function looksLikeHostPath(p: string) {
  if (p.startsWith("/Users/") || p.startsWith("/Volumes/")) return true
  if (/^[A-Za-z]:\\/.test(p) || p.startsWith("\\\\")) return true
  if (p.startsWith("/mnt/") && /\/mnt\/[a-z]\//i.test(p)) return true
  return false
}

function isAllowedImage(p: string) {
  return /\.(png|jpe?g|webp|gif)$/i.test(p)
}

function fileUriToPath(uri: string) {
  if (!uri.startsWith("file://")) return uri
  try {
    return decodeURIComponent(uri.replace(/^file:\/\//, ""))
  } catch {
    return uri
  }
}

export const HakimHostAttachments: Plugin = async () => {
  return {
    "chat.message": async (_input, output) => {
      const cfg = readConfig()
      if (!cfg) return

      const attachments: { mime: string; filename: string; url: string }[] = []
      const replaced = new Map<string, string>()
      const parts = output.parts

      for (const part of parts) {
        if (part.type !== "text") continue
        if (part.synthetic || part.ignored) continue

        const text = part.text
        const tokens = tokenize(text)
        let nextText = text
        let delta = 0

        for (const t of tokens) {
          const originalToken = t.token
          if (!originalToken) continue

          let candidate = stripQuotes(originalToken)
          candidate = fileUriToPath(candidate)
          candidate = unescapeToken(candidate)

          if (!looksLikeHostPath(candidate)) continue
          if (!isAllowedImage(candidate)) continue
          if (replaced.has(originalToken)) continue

          try {
            if (fs.existsSync(candidate)) continue
          } catch {
          }

          const headers: Record<string, string> = { "Content-Type": "application/json" }
          if (cfg.token) headers.Authorization = `Bearer ${cfg.token}`

          let resp: Response
          try {
            resp = await fetch(`${cfg.url.replace(/\/$/, "")}/v1/read`, {
              method: "POST",
              headers,
              body: JSON.stringify({ path: candidate }),
            })
          } catch {
            continue
          }
          if (!resp.ok) continue

          let data: any
          try {
            data = await resp.json()
          } catch {
            continue
          }
          if (!data || typeof data !== "object") continue
          if (typeof data.data_base64 !== "string" || typeof data.mime !== "string") continue

          const filename = typeof data.filename === "string" && data.filename ? data.filename : path.basename(candidate)
          attachments.push({
            mime: data.mime,
            filename,
            url: `data:${data.mime};base64,${data.data_base64}`,
          })

          const marker = `[attached image: ${filename}]`
          const start = t.start + delta
          const end = t.end + delta
          nextText = nextText.slice(0, start) + marker + nextText.slice(end)
          delta += marker.length - (end - start)
          replaced.set(originalToken, marker)
        }

        if (nextText !== text) {
          part.text = nextText
        }
      }

      if (attachments.length === 0) return
      for (const a of attachments) {
        output.parts.push({
          type: "file",
          mime: a.mime,
          filename: a.filename,
          url: a.url,
        })
      }
    },
  }
}
EOF
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
