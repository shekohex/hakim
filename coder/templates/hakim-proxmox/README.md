---
display_name: Hakim AI (Proxmox)
description: Proxmox LXC template using OCI images from GHCR
icon: https://cdn.simpleicons.org/proxmox?viewbox=auto
verified: false
tags: [proxmox, lxc, ai]
---

# Hakim Proxmox Template

Provisions Hakim workspaces on Proxmox LXC using OCI templates pulled from GHCR.

## How It Works

1. Proxmox pulls OCI images from GHCR and stores them in template storage (`vztmpl`).
2. `coder/templates/hakim-proxmox/main.tf` selects a variant + template tag and references a shared pre-pulled template id.
3. Hakim image entrypoint starts `coder agent` automatically when `CODER_AGENT_URL` and `CODER_AGENT_TOKEN` are present.
4. Provisioner-side post-create agent bootstrap is applied through `scripts/bootstrap-agent-env.sh` using bash+curl (no python dependency).
5. Template runs the same module stack used by Docker template (`opencode`, `openchamber`, `openclaw-node`, `code-server`, etc).

## Design Goals

- Keep `coder/templates/hakim` unchanged.
- Provide a parallel Proxmox substrate: `coder/templates/hakim-proxmox`.
- Keep variant behavior as close as possible to DevContainer variants.
- Keep security defaults conservative (`unprivileged = true`, nesting off by default).
- Remove SSH bootstrap and rely on coder-agent-native containers.

## OCI Image Contract

- Variants: `base`, `php`, `dotnet`, `js`, `rust`, `elixir`
- GHCR images: `ghcr.io/shekohex/hakim-<variant>:latest`
- Base image: `ghcr.io/shekohex/hakim-base:latest`
- Proxmox template name: `hakim-<variant>_latest.tar`

## Required Template Inputs

- Proxmox API endpoint/token
- Node name, container datastore, template datastore
- Optional `/home/coder` persistence (`enable_home_disk`)
- Optional existing home mount source override (`proxmox_home_volume_id`)
- Network bridge and optional VLAN
- Variant selector (`image_variant`) + shared `template_tag` or custom `custom_template_file_id`
- Optional forced rebuild counter (`workspace_rebuild_generation`)

## Pull OCI Templates into Proxmox

Run once on the Proxmox host:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh
```

Show flags:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh --help
```

Pull a specific variant:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh --variant js --tag latest
```

Pull multiple variants:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh --variants base,js,elixir --tag latest
```

Pull a single explicit image reference:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh --image ghcr.io/shekohex/hakim-elixir:latest
```

Replace existing templates:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh --variants base,js --tag latest --force-replace
```

Check remote GHCR digest and replace only when changed:

```bash
./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh --variants base,php,dotnet,js,rust,elixir --tag latest --check-remote-digest --use-gh-auth-token
```

Optional environment overrides still supported:

```bash
NODE_NAME=bigboss DATASTORE_ID=local ./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh
```

Pull a specific tag:

```bash
NODE_NAME=bigboss DATASTORE_ID=local TEMPLATE_TAG=v2026.02.14 ./coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh
```

Verify templates:

```bash
pvesm list local --content vztmpl | rg 'hakim-.*_latest.tar'
```

## Build and Publish Images

Build script:

```bash
./scripts/build.sh
```

This builds and publishes `hakim-base`, `hakim-tooling`, and all variants.

## Update Existing Workspaces

1. Build and publish new image tag.
2. Pull that tag into Proxmox templates (`TEMPLATE_TAG=<new-tag>`).
3. Update workspace `template_tag` to the new tag and apply.
4. If keeping same tag name (for example `latest`), increment `workspace_rebuild_generation` to force CT recreation.
5. To preserve user data, enable home persistence so `/home/coder` is bind-mounted and survives CT replacement.

## Create a New Variant

To add variant `go`, update all of these:

1. Variant image:
   - Add `devcontainers/.devcontainer/images/go/.devcontainer/devcontainer.json`.
2. Coder Proxmox template:
   - Add option in `coder/templates/hakim-proxmox/main.tf` `image_variant` parameter.
   - Ensure `template_tag` naming stays `hakim-<variant>_<tag>.tar`.
   - Add module gates/presets if needed.
3. Pull script:
   - Add variant in `coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh`.
4. Validate:

```bash
bash -n coder/templates/hakim-proxmox/scripts/pull-oci-templates.sh
terraform fmt -recursive
terraform init && terraform validate
```

## FAQ

Q: Are templates still distrobuilder artifacts?

- No. OCI images from GHCR are now the source of truth.
- Proxmox converts OCI images into `vztmpl` tar templates.

Q: Does CI/CD publish Coder templates too?

- Yes. `.github/workflows/publish-template.yaml` discovers templates under `coder/templates/*`, validates them, then runs `coder templates push`.
- It now hard-checks both `hakim` and `hakim-proxmox` exist.

Q: Does this replace Docker template?

- No. Docker template stays intact and published in parallel.

Q: How do I force a specific pre-uploaded template in Proxmox?

- Set `image_variant = custom` and provide `custom_template_file_id` (for example `local:vztmpl/hakim-elixir_latest.tar`).

Q: Does workspace creation pull from GHCR directly?

- No. Workspace creation reads an already-present Proxmox template file id.
- Pulling from GHCR is an explicit host operation via `pull-oci-templates.sh`.

Q: If I pull a refreshed image, do existing workspaces update automatically?

- No. Existing CT rootfs is immutable.
- Recreate the container (change `template_tag` or increment `workspace_rebuild_generation`).

Q: Is there digest/hash comparison with GHCR and Docker-like layer cache?

- Proxmox stores pulled OCI as `vztmpl` tar files.
- It does not transparently roll running CTs forward; updates are explicit pulls + CT recreation.
- Re-pull behavior is controlled operationally (`--force-replace` or `--check-remote-digest` in pull script).

Q: Does stopping a workspace delete the CT and disks?

- No. The CT now stays managed permanently and only toggles running state with Coder start/stop (`started = transition == "start"`).
- Root disk and optional `/home/coder` disk are kept across stop/start and host reboot.

Q: How do I keep user data when rebuilding/replacing a workspace container?

- Use `enable_home_disk = true`.
- Default behavior creates a per-workspace bind mount at `/var/lib/vz/hakim-homes/<owner>/<workspace>` and mounts it to `/home/coder`.
- You can set `proxmox_home_volume_id` explicitly to mount an existing source instead (volume id or absolute host path).

Q: What does `proxmox_home_volume_id` look like?

- It must be the mount source value Proxmox uses for `/home/coder`.
- Volume example: `local-lvm:subvol-300-disk-1`.
- Bind path example: `/var/lib/vz/hakim-homes/alice/my-workspace`.

Q: How do I get `proxmox_home_volume_id` from CLI (`pct config <ctid>`) ?

- Use a real CT id (do not type angle brackets literally).
- Example: `pct config 300 | rg '^mp[0-9]+:'`.
- Find the line with `mp=/home/coder`.
- Copy only the source before the first comma.
- Example: `mp0: local-lvm:subvol-300-disk-1,mp=/home/coder,backup=1,size=30G` -> use `local-lvm:subvol-300-disk-1`.
- Exact filter example: `pct config 300 | rg '^mp[0-9]+:.*mp=/home/coder'`.
- If `rg` is unavailable: `pct config 300 | grep -E '^mp[0-9]+:.*mp=/home/coder'`.

Q: Can you show full CLI examples for volume id and bind mount?

- Existing volume-backed home mount:
  - `pct config 300 | rg '^mp[0-9]+:.*mp=/home/coder'`
  - Output: `mp0: local-lvm:subvol-300-disk-1,mp=/home/coder,backup=1,size=30G`
  - Set `proxmox_home_volume_id = local-lvm:subvol-300-disk-1`
- Bind-mounted home directory:
  - `pct config 300 | rg '^mp[0-9]+:.*mp=/home/coder'`
  - Output: `mp0: /mnt/pve/data/coder-homes/ws-raptors,mp=/home/coder,backup=1`
  - Set `proxmox_home_volume_id = /mnt/pve/data/coder-homes/ws-raptors`

Q: Can I extract only the source field automatically?

- Yes:
  - `pct config 300 | rg '^mp[0-9]+:.*mp=/home/coder' | cut -d' ' -f2 | cut -d',' -f1`
- Example output: `local-lvm:subvol-300-disk-1`

Q: How do I get `proxmox_home_volume_id` from Proxmox UI?

- Open `Node -> CT -> Resources`.
- Find the mount point whose mount path is `/home/coder`.
- Open/edit it and copy the Volume/source value exactly.
- Do not include mount options like `,mp=/home/coder,...`; only the source itself.

Q: How do I clean up home data after deleting a workspace?

- If you used a bind path, remove it explicitly on the Proxmox host (for example `rm -rf /path/to/home-bind`).
- If you used an external volume id via `proxmox_home_volume_id`, remove it explicitly from Proxmox storage when you are sure the workspace is gone.

Q: Is there a helper script for managed-volume cleanup?

- Not in the default bind-mount flow.
- If you use `proxmox_home_volume_id` with a storage volume id, clean it up directly in Proxmox when no longer needed.
