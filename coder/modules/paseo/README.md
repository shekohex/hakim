---
display_name: Paseo
icon: https://app.paseo.sh/apple-touch-icon.png
description: Install Paseo and expose its bundled web UI
verified: false
tags: [agent, paseo, web, ai]
---

# Paseo

Install `@getpaseo/cli@latest` with Bun, run it as `paseo.service`, and expose the bundled web UI through the owner-authenticated `paseo` Coder subdomain.

```tf
module "paseo" {
  source   = "github.com/shekohex/hakim//coder/modules/paseo?ref=main"
  agent_id = coder_agent.main.id
  enabled  = true
}
```

## Requirements

- Bun
- systemd
- sudo access for installing the service

## Service

The module installs and enables `/etc/systemd/system/paseo.service`, running:

```bash
paseo daemon start --foreground --home ~/.paseo --listen 127.0.0.1:6767 --no-relay --web-ui --hostnames true
```

Coder proxies `http://localhost:6767/` through the `paseo` subdomain and handles access control.

Set `enabled = false` to stop and disable `paseo.service` without uninstalling Paseo.
