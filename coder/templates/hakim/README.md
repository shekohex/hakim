---
display_name: Hakim AI
description: Universal Coder template with OpenCode agent and multiple language variants
icon: https://cdn.simpleicons.org/kongregate?viewbox=auto
verified: true
tags: [docker, container, ai]
---

# Hakim Universal Template

Pre-built DevContainer images for AI-powered development.

## Features

- **Variants**: Base, PHP (Laravel), .NET, Node.js/Bun, Rust, or Custom Image
- **AI Integration**: OpenCode agent with embedded web UI (port 4096)
- **MCP Support**: Task reporting via Coder MCP server
- **Security**: Optional Vault integration, masked secrets
- **Persistence**: `/home/coder` volume persisted

## Quick Start

1. Select "Hakim Universal" template
2. Choose environment variant
3. (Optional) Paste `auth.json` for OpenCode authentication
4. (Optional) Provide Git URL to auto-clone

## Workspace Presets

- Laravel Quick Start
- .NET Quick Start  
- Node.js/Bun Quick Start
- Rust Quick Start
- Minimal Environment

## OpenCode Integration

This template uses a local `opencode` module that runs `opencode serve` directly without the `agentapi` wrapper. The web UI is available on port 4096 with healthcheck at `/project/current`.
