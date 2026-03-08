---
display_name: SSH keys
description: Configures the workspace to use your Coder SSH key as ~/.ssh/id_ed25519
icon: /icon/terminal.svg
verified: true
tags: [helper, ssh]
---

# ssh-keys

This module downloads your SSH key from Coder and installs it as `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub`.
It requires `curl` and `jq` to be installed inside your workspace.

Please observe that using the SSH key that's part of your Coder account as a general-purpose SSH key means that in the event of a breach of your Coder account, or a malicious admin, someone could perform SSH authentication pretending to be you.

This module may overwrite an existing `~/.ssh/id_ed25519` keypair if you enable it in a workspace that already has one.

```tf
module "ssh-keys" {
  count    = data.coder_workspace.me.start_count
  source   = "github.com/shekohex/hakim//coder/modules/ssh-keys?ref=main"
  agent_id = coder_agent.main.id
}
```
