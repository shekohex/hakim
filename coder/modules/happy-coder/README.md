---
display_name: Happy
icon: https://app.happy.engineering/favicon.ico
description: Run Happy ACP against a local OpenCode server
verified: false
tags: [agent, happy, opencode, ai, acp]
---

# Happy Coder

Run [Happy CLI](https://happy.engineering/) in your workspace. This module installs `happy-coder`, starts a background supervisor, and auto-connects Happy to the running OpenCode ACP endpoint on port 4096 by default.

```tf
module "happy_coder" {
  source   = "github.com/shekohex/hakim//coder/modules/happy-coder?ref=main"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
}
```

## Prerequisites

- OpenCode running and reachable from the workspace
- Happy authenticated via `happy auth` with credentials stored in `HAPPY_HOME_DIR` (default: `~/.happy/access.key`)

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `happy_coder_version` | npm version or dist-tag to install | `0.15.0-beta.0` |
| `happy_server_url` | Happy API server URL | `https://api.cluster-fluster.com` |
| `happy_webapp_url` | Happy web app URL | `https://app.happy.engineering` |
| `happy_home_dir` | Happy home directory | `~/.happy` |
| `happy_disable_caffeinate` | Disable macOS sleep prevention | `false` |
| `happy_experimental` | Enable experimental features | `false` |
| `opencode_port` | OpenCode ACP attach port | `4096` |
| `workdir` | Working directory | required |

## Troubleshooting

Check logs at `/tmp/happy-coder-supervisor.log`, `/tmp/happy-coder-daemon.log`, and `/tmp/happy-coder-session.log` within your workspace.

## References

- [Happy CLI](https://github.com/slopus/happy-cli)
- [OpenCode ACP](https://opencode.ai)
