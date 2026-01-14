---
display_name: OpenChamber
icon: https://raw.githubusercontent.com/btriapitsyn/openchamber/refs/heads/main/docs/references/badges/openchamber-logo-dark.svg
description: Run OpenChamber web UI for OpenCode
verified: false
tags: [agent, openchamber, opencode, ai]
---

# OpenChamber

Run [OpenChamber](https://github.com/btriapitsyn/openchamber) in your workspace. This module runs `openchamber` on port 6904.

```tf
module "openchamber" {
  source   = "github.com/shekohex/hakim//coder/modules/openchamber?ref=main"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
}
```

## Prerequisites

- OpenCode running (via the OpenCode module)

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `port` | Web server port | `6904` |
| `ui_password` | Optional UI password | `""` |
| `workdir` | Working directory | required |

## Troubleshooting

Check logs at `/tmp/openchamber-serve.log` within your workspace.

## References

- [OpenChamber README](https://github.com/btriapitsyn/openchamber)
