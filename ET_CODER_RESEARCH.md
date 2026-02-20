# EternalTerminal + Coder Research

Date: 2026-02-20

## Goal

Provide "indestructible" `ssh <workspace>.coder` behavior across laptop sleep/network changes by introducing Eternal Terminal (ET), with minimal template/image changes, no hardcoded workspace IPs/hostnames, and preserving Coder-based workspace access.

## Constraints and Preferences

- Use `ssh <ws>.coder` as the normal UX.
- Avoid direct workspace network dependency from laptop.
- Avoid hardcoded workspace IP/host values.
- Prefer Coder-authenticated transport/bootstrap paths.
- Accept running `etserver` (port 2022) and locked-down `sshd` (port 2244) in workspace.

## External Research Findings

### EternalTerminal upstream

- `MisterTea/EternalTerminal#249` (merged) added:
  - `--ssh-socket`
  - parsing `ForwardAgent` and `IdentityAgent` from ssh config
  - precedence behavior between CLI and ssh config
- `MisterTea/EternalTerminal#262` (closed) was resolved by `#249`.
- `MisterTea/EternalTerminal#594` (merged) fixed `IdentityAgent` tilde expansion bug (`~` paths).
- `MisterTea/EternalTerminal#263` was a duplicate approach and not merged.
- ET supports passing SSH options (`--ssh-option`) and includes `serverfifo`/`jserverfifo` features in client/server CLI.

### Coder upstream

- `coder/coder#18101` remains open (reopened) for indestructible IDE connections.
- Commented PoC (by Coder team) used:
  - workspace `etserver:2022`
  - workspace `sshd:2244`
  - Coder Desktop routing
  - ET tunnel to local ssh endpoint
- `coder/coder#18673` is only a partial reconnect improvement (not ET-equivalent resilience).
- `coder/coder#18101` has sub-issues:
  - `#19977` (backed pipe base) closed
  - `#19978-#19981` still open (agent/api + ssh/stdio + ssh command + port-forward integration)
- Conclusion: native Coder "ET-like" connection resilience is not fully shipped yet.

### VS Code side

- `coder/vscode-coder#413` still has ongoing reports of disconnect/reload behavior.
- Team discussion points to upstream VS Code reconnection token/time-window behavior.
- ET continues to be considered a practical workaround pattern.

## Current Hakim Repo Observations

- Proxmox template explicitly says SSH bootstrap was removed and coder-agent-native flow is preferred:
  - `coder/templates/hakim-proxmox/README.md`
- Base image currently includes `openssh-client` only, not `openssh-server` or ET:
  - `devcontainers/base/Dockerfile`
- Existing templates already provide startup extension points and modular scripts.

## Feasibility of "automatic" local setup via SSH config

OpenSSH does not provide true pre/post connection hooks with lifecycle semantics for external daemons.

What is feasible:

- Use a custom `ProxyCommand` script as the automation entrypoint.
- In that script, ensure local background processes are running:
  1. `coder port-forward <ws> --tcp <local_et_port>:2022`
  2. `et -N -t <local_ssh_port>:2244 ...`
- Then `exec` a raw connector (`nc 127.0.0.1 <local_ssh_port>`) so SSH uses that stream.

This effectively gives a "before-command" behavior through ProxyCommand startup checks.

Potential "after-command" behavior is best handled by idle cleanup in the same helper (PID/port checks + stale process reap), not by SSH hooks.

## Proposed Architecture

### Workspace side

- Add ET module (`coder/modules/et`) to:
  - configure and launch `etserver` on `127.0.0.1:2022`
  - configure and launch hardened `sshd` on `127.0.0.1:2244`
  - lock down sshd (no password auth, no root login, restricted user)

### Local side

- Add a local `ProxyCommand` helper script that:
  - derives workspace name from `%h` (`<ws>.coder`)
  - starts/ensures Coder port-forward for ET port
  - starts/ensures ET tunnel for local SSH endpoint
  - connects stdin/stdout to local tunneled sshd port

### Image side

- Add ET installation in its own isolated Docker build step/layer.
- Add `openssh-server` to runtime image.

## Security Notes

- Bind ET and sshd to loopback inside workspace (`127.0.0.1`) to prevent unintended exposure.
- Keep `sshd` hardened:
  - `PermitRootLogin no`
  - `PasswordAuthentication no`
  - `KbdInteractiveAuthentication no`
  - `PubkeyAuthentication yes`
  - `AllowUsers coder`
- Use dedicated config and PID files to avoid interfering with system sshd.

## Open Questions / Known Tradeoffs

- Inner sshd authentication still requires a usable SSH identity strategy.
  - This can be automated by helper tooling, but it is still SSH pubkey auth at the sshd layer.
- Local helper must manage port allocation and process lifecycle robustly.
- If Coder later ships immortal-stream support for all ssh/port-forward paths, this ET approach may become optional legacy compatibility.

## Why this plan is minimal-change

- Reuses existing Coder SSH host pattern and user habit (`ssh <ws>.coder`).
- Adds one new module and targeted image/tooling changes.
- Avoids changing core Coder behavior or requiring direct workspace network access.
- Keeps ET integration additive and feature-flagged at template level.

## Implementation Plan

1. Add `coder/modules/et` with install/start scripts and hardened runtime config generation.
2. Add ET + `openssh-server` to `devcontainers/base` in isolated tooling step.
3. Wire module into both templates (`hakim`, `hakim-proxmox`) behind a boolean parameter.
4. Add local ProxyCommand helper script for auto `coder port-forward` + `et` orchestration.
5. Provide concise usage wiring for SSH config to route `*.coder` via helper.
6. Validate with terraform fmt + shell checks.
