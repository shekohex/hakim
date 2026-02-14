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
4. Template runs the same module stack used by Docker template (`opencode`, `openchamber`, `openclaw-node`, `code-server`, etc).

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
- Optional dedicated home volume (`enable_home_disk`, `home_disk_gb`, `proxmox_home_datastore_id`)
- Optional existing home volume reattach (`proxmox_home_volume_id`)
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
5. To preserve user data, keep `/home/coder` on a dedicated volume and set `proxmox_home_volume_id` before rebuild.

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

- Use `enable_home_disk = true` so `/home/coder` is a separate mount.
- Before replacement, note the existing home volume id (for example `local-lvm:subvol-<vmid>-disk-1`) and set `proxmox_home_volume_id` to reattach it.
