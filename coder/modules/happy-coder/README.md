---
display_name: Happy
icon: https://app.happy.engineering/favicon.ico
description: Run Happy ACP against a local OpenCode server
verified: false
tags: [agent, happy, opencode, ai, acp]
---

# Happy Coder

Run [Happy CLI](https://happy.engineering/) in your workspace. This module installs `happy-coder` and a `happy-opencode` helper that starts a background Happy ACP session for the current working directory against the running OpenCode server on port 4096 by default.

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

## Quick Start

```bash
happy auth
cd /home/coder/project
happy-opencode start
```

Useful commands:

- `happy-opencode start` - start a background ACP session for the current directory
- `happy-opencode status` - show the tracked session, PID, and log path for the current directory
- `happy-opencode stop` - stop the tracked session for the current directory
- `happy-opencode restart` - restart the tracked session for the current directory
- `happy-opencode list` - list all sessions known to the Happy daemon

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

Use `happy-opencode logs` to print the current directory log path, then inspect that file. Session state is stored under `HAPPY_HOME_DIR/hakim/opencode/`.

## References

- [Happy CLI](https://github.com/slopus/happy-cli)
- [OpenCode ACP](https://opencode.ai)
