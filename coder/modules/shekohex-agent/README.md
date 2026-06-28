---
display_name: Shekohex Agent
icon: /icon/terminal.svg
description: Install Shekohex Pi coding agent CLI
verified: false
tags: [agent, pi, cli, ai]
---

# Shekohex Agent

Install Shekohex Pi coding agent CLI in your workspace with Bun.

```tf
module "shekohex_agent" {
  source    = "github.com/shekohex/hakim//coder/modules/shekohex-agent?ref=main"
  agent_id  = coder_agent.main.id
  auth_json = data.coder_parameter.shekohex_agent_auth.value
}
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `auth_json` | Pi auth JSON written to `~/.pi/agent/auth.json` when file does not exist | `{}` |
| `install_shekohex_agent` | Install the CLI | `true` |
| `pre_install_script` | Custom script before install | `null` |
| `post_install_script` | Custom script after install | `null` |

## Healthcheck

The module runs `pi --help` after installation.
