---
display_name: T3 Code
icon: https://t3.codes/apple-touch-icon.png
description: Install and run official T3 Code nightly
verified: false
tags: [agent, t3code, web, ai]
---

# T3 Code

Install official [`t3@nightly`](https://www.npmjs.com/package/t3?activeTab=versions) with Bun, run it as `t3code.service`, and expose it through a public Coder app at the `t3` subdomain. Requires Bun, Node.js 20.11+, systemd, and passwordless sudo.

```tf
module "t3code" {
  source   = "github.com/shekohex/hakim//coder/modules/t3code?ref=main"
  agent_id = coder_agent.main.id
  enabled  = true
  port     = 3157
}
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `agent_id` | Coder agent ID | Required |
| `enabled` | Install and run T3 Code; stop service when false | `true` |
| `port` | Server and Coder app port (1–65535) | `3157` |

## Service

The module installs and enables `/etc/systemd/system/t3code.service`, running:

```bash
t3 serve --host 0.0.0.0 --lan --port 3157 --no-browser
```

Starts automatically with the workspace, runs in the foreground under systemd, and restarts on failure. The `t3` CLI is available at `/usr/local/bin/t3`.

Coder proxies `http://localhost:3157/` through public `t3` subdomain. Set `port` to change both the service and proxy port. T3 Code handles authentication; use `t3 pair` to generate a connection link.

Inspect service and stream logs:

```bash
sudo systemctl status t3code.service
sudo journalctl -u t3code.service -f
```

Set `enabled = false` to stop and disable `t3code.service` without uninstalling T3 Code.

## Update

Run:

```bash
t3-update
```

The command installs the latest official nightly with Bun, restarts `t3code.service`, and verifies the service is active. No GitHub Packages token is needed.
