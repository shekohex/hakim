---
display_name: T3 Code
icon: https://t3.codes/apple-touch-icon.png
description: Install and run the T3 Code fork
verified: false
tags: [agent, t3code, web, ai]
---

# T3 Code

Install the T3 Code fork with Bun, run it as `t3code.service`, and expose it through a public Coder app at the `t3` subdomain.

```tf
module "t3code" {
  source   = "github.com/shekohex/hakim//coder/modules/t3code?ref=main"
  agent_id = coder_agent.main.id
}
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `agent_id` | Coder agent ID | Required |

## Service

The module installs and enables `/etc/systemd/system/t3code.service`, running:

```bash
t3 serve --host 0.0.0.0 --port 1337
```

Coder proxies `http://localhost:1337/` through public `t3` subdomain. T3 Code handles authentication.

## Update

Run:

```bash
t3-update
```

The command reinstalls the latest fork package, restarts `t3code.service`, and verifies the service is active. It uses the same GitHub Packages authentication as the installer: an exported `NODE_AUTH_TOKEN`, `NPM_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN`, falling back to `gh auth token`.
