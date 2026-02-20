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
- **Resilient SSH (Optional)**: ET transport with loopback `etserver:2022` + internal `sshd:2244`

## Quick Start

1. Select "Hakim Universal" template
2. Choose environment variant
3. (Optional) Paste `auth.json` for OpenCode authentication
4. (Optional) Provide Git URL to auto-clone

## Optional ET SSH Mode

Set `enable_et = true` to run loopback `etserver` (`127.0.0.1:2022`) and internal hardened `sshd` (`127.0.0.1:2244`) inside the workspace.

## Workspace Presets

- Laravel Quick Start
- .NET Quick Start  
- Node.js/Bun Quick Start
- Rust Quick Start
- Minimal Environment

## OpenCode Integration

This template uses the `opencode` module from the GitHub repository. The web UI is available on port 4096 with healthcheck at `/project/current`.

## Docker Support (DooD)

This template enables **Docker outside of Docker (DooD)**. The host's Docker socket is mounted into the workspace, allowing you to run sibling containers.

### Networking & Isolation

Each workspace is assigned a **private Docker network**. To run sidecar containers (e.g. Redis, Postgres) that are accessible from your workspace but isolated from others, attach them to your workspace's network.

#### Running a Sidecar Service (Recommended)

1.  **Find your network name**:
    Run `docker network ls` inside your workspace. You will see a network named like `coder-<owner>-<workspace>`.

2.  **Run the container**:
    ```bash
    # Option A: Attach to your private network (Recommended)
    docker run -d --name redis --network coder-$(whoami)-$(hostname) redis

    # Option B: Attach directly to your container's namespace (Easiest)
    # This makes the service available on "localhost" inside your workspace
    docker run -d --network container:$(hostname) redis
    ```

3.  **Access the service**:
    *   If using **Option A**: Access via the container name (e.g., `redis:6379`).
    *   If using **Option B**: Access via `localhost:6379`.

### Important Notes

*   **Avoid `-p` (Port Mapping)**: Do not use `docker run -p 8080:8080 ...`. This binds the port on the **HOST** machine, which may cause conflicts with other users. Always use the network attachment methods above.
*   **Permissions**: The `coder` user has full access to the Docker socket via `sudo`.
