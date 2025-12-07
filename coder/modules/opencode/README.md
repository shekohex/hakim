---
display_name: OpenCode
icon: /icons/opencode.svg
description: Run OpenCode AI coding assistant with embedded web UI
verified: true
tags: [agent, opencode, ai, tasks]
---

# OpenCode

Run [OpenCode](https://opencode.ai) AI coding assistant in your workspace. This module runs `opencode serve` directly, providing an embedded web UI on port 4096.

```tf
module "opencode" {
  source   = "../../modules/opencode"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
}
```

## Prerequisites

- **Authentication credentials** - OpenCode auth.json file required for non-interactive authentication: `$HOME/.local/share/opencode/auth.json`

## Examples

### Basic Usage with Tasks

```tf
resource "coder_ai_task" "task" {
  app_id = module.opencode.task_app_id
}

module "opencode" {
  source   = "../../modules/opencode"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
  ai_prompt = coder_ai_task.task.prompt

  auth_json = <<-EOT
{
  "anthropic": {
    "type": "api",
    "key": "sk-ant-api03-xxx"
  }
}
EOT

  config_json = jsonencode({
    "$schema" = "https://opencode.ai/config.json"
    model     = "anthropic/claude-sonnet-4-20250514"
  })
}
```

### CLI Mode

```tf
module "opencode" {
  source       = "../../modules/opencode"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder"
  report_tasks = false
  cli_app      = true
}
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `port` | Web server port | `4096` |
| `hostname` | Web server hostname | `0.0.0.0` |
| `workdir` | Working directory | required |
| `report_tasks` | Enable MCP task reporting | `true` |
| `cli_app` | Create CLI app | `false` |

## Troubleshooting

Check logs at `/tmp/opencode-serve.log` within your workspace.

## References

- [OpenCode Documentation](https://opencode.ai/docs)
- [OpenCode JSON Config](https://opencode.ai/docs/config/)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
