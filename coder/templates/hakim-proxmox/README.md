---
display_name: Hakim AI (Proxmox)
description: Proxmox LXC template using Distrobuilder golden images
icon: https://cdn.simpleicons.org/proxmox?viewbox=auto
verified: false
tags: [proxmox, lxc, ai]
---

# Hakim Proxmox Template

Provisions Hakim workspaces on Proxmox LXC using Distrobuilder-built golden templates.

## How It Works

1. Build golden LXC artifacts with Distrobuilder from `distrobuilder/hakim.yaml`.
2. Publish artifacts as `hakim-<variant>-<release>-<arch>.tar.xz` plus `sha256sums.txt`.
3. Store artifacts in Proxmox template storage (`vztmpl`).
4. `coder/templates/hakim-proxmox/main.tf` selects variant, optionally downloads artifact URL to Proxmox datastore, and creates LXC.
5. Template bootstraps Coder agent, then starts the same module stack used by Docker template (`opencode`, `openchamber`, `openclaw-node`, `code-server`, etc).

## Design Goals

- Keep `coder/templates/hakim` unchanged.
- Provide a parallel Proxmox substrate: `coder/templates/hakim-proxmox`.
- Keep variant behavior as close as possible to DevContainer variants.
- Keep security defaults conservative (`unprivileged = true`, nesting off by default).

## Build and Artifact Contract

- Variants: `base`, `php`, `dotnet`, `js`, `rust`, `elixir`
- Artifact: `hakim-<variant>-<release>-<arch>.tar.xz`
- Checksum file: `sha256sums.txt`
- Build script (unified): `distrobuilder/scripts/build.sh` (supports --all, --cached, --variant flags)

## Required Template Inputs

- Proxmox API endpoint/token
- Node name, container datastore, template datastore
- Optional dedicated home volume (`enable_home_disk`, `home_disk_gb`, `proxmox_home_datastore_id`)
- Optional existing home volume reattach (`proxmox_home_volume_id`)
- Network bridge and optional VLAN
- Variant template URLs (`template_url_*`) or custom `template_file_id`
- Root SSH key used for initial agent bootstrap

## Build the Golden Images

### In GitHub Actions

- Workflow: `.github/workflows/build-lxc-templates.yml`
- Builds all variants in matrix.
- Verifies per-variant checksums and consolidated checksums.
- Uploads artifacts to GitHub Actions artifacts.

### Manually (Linux/Proxmox host)

```bash
# Install distrobuilder from source (no snap required)
./scripts/install-distrobuilder.sh

# Build templates
./distrobuilder/scripts/build.sh --variant base           # Build single variant
./distrobuilder/scripts/build.sh --all                    # Build all variants
./distrobuilder/scripts/build.sh --all --cached           # Build all with cache
./distrobuilder/scripts/build.sh --variant elixir --cached # Build elixir with cache
```

The install script will:
- Install Go and build dependencies
- Compile distrobuilder from source
- Install to `/usr/local/bin/distrobuilder`
- Check Go version and upgrade if needed (requires 1.21+)

Outputs are written under `distrobuilder/out/<variant>/`.

## Put Artifacts in Proxmox as CT Templates

The `.tar.xz` artifact is a Proxmox-compatible LXC rootfs template. It contains the raw filesystem (not nested archives), ready for `pct create`.

**Template Format:**
- The artifact is the raw `rootfs.tar.xz` (extracted from distrobuilder output)
- Proxmox can use it directly with `--ostype debian`
- No conversion or extraction step required

Typical flow:

1. Build artifact(s).
2. Copy artifact to Proxmox storage content type `vztmpl`.
3. Verify visibility:

```bash
pveam list <storage>
# or
pvesm list <storage> --content vztmpl
```

If storage is `local`, files typically live at `/var/lib/vz/template/cache/`.

## Add a New Package to an Existing Variant

Use this rule of thumb:

- Base/common packages for all variants: add in `distrobuilder/hakim.yaml` under `packages.sets[0].packages`.
- Variant-specific packages/tooling: add in `distrobuilder/scripts/actions/post-packages.sh` inside that variant branch.

Example: add `ripgrep` to all variants.

1. Edit `distrobuilder/hakim.yaml` and add `ripgrep` in base packages.
2. Run syntax checks:

```bash
ruby -e 'require "yaml"; YAML.load_file("distrobuilder/hakim.yaml"); puts "ok"'
bash -n distrobuilder/scripts/actions/post-packages.sh
```

Example: add package only to `php` variant.

1. Edit `distrobuilder/scripts/actions/post-packages.sh` in `install_php_stack()`.
2. Add apt install entry there.
3. Re-run shell syntax check.

## Create a New Variant

To add variant `go`, update all of these:

1. Distrobuilder build contract:
   - `distrobuilder/scripts/build.sh` variant allowlist (in the case statement).
2. Variant install logic:
   - Add branch in `distrobuilder/scripts/actions/post-packages.sh`.
3. Coder Proxmox template:
   - Add option in `coder/templates/hakim-proxmox/main.tf` `image_variant` parameter.
   - Add `template_url_go` parameter.
   - Add `go` in `template_url_map` local.
   - Add module gates/presets if needed.
4. CI build matrix:
   - Add variant in `.github/workflows/build-lxc-templates.yml` matrix and verify loops.
5. Validate:

```bash
bash -n distrobuilder/scripts/build.sh distrobuilder/scripts/actions/post-packages.sh
ruby -e 'require "yaml"; YAML.load_file("distrobuilder/hakim.yaml"); puts "ok"'
terraform fmt -recursive
terraform init && terraform validate
```

## FAQ

Q: Do we cache builds like Docker layers?

- Not in the Docker-layer sense.
- Distrobuilder builds rootfs images, not image layers.
- It can reuse downloaded source artifacts on the same build host (`--sources-dir` + `--keep-sources` behavior), but package installation still runs each build.
- In GitHub Actions runners (ephemeral), each run is effectively a fresh build.

Q: Does every change trigger full rebuild of everything?

- In CI, yes for the current matrix workflow: each variant job builds that variant from scratch on a fresh runner.
- Local/manual builds can reuse host-side source cache if the same host keeps cache.

Q: Are LXC artifacts automatically uploaded to Proxmox by CI?

- No. Current CI uploads artifacts to GitHub Actions artifacts only.
- Promotion into Proxmox storage is an explicit operational step.

Q: Does CI/CD publish Coder templates too?

- Yes. `.github/workflows/publish-template.yaml` discovers templates under `coder/templates/*`, validates them, then runs `coder templates push`.
- It now hard-checks both `hakim` and `hakim-proxmox` exist.

Q: Does this replace Docker template?

- No. Docker template stays intact and published in parallel.

Q: How do I force a specific pre-uploaded template in Proxmox?

- Set `image_variant = custom` and provide `custom_template_file_id` (for example `local:vztmpl/hakim-base-trixie-amd64.tar.xz`).

Q: Can I use `template_release=trixie` right now?

- Yes. The template uses `ostype=unmanaged` for `trixie` and `ostype=debian` for older releases.
- Rebuild and deploy latest `trixie` artifacts before creating workspaces.

Q: Why do we still need SSH key input?

- Initial Coder agent bootstrap is done through Terraform `remote-exec` over SSH before workspace apps/modules can start.

Q: How does bootstrap authentication work now?

- First bootstrap uses root SSH with key and password fallback.
- For `trixie`, initial password fallback is `password` (set in image build) because Proxmox unmanaged mode does not inject credentials.
- For non-`trixie`, password fallback is derived from bootstrap key material and injected through Proxmox `user_account.password`.
- Bootstrap then installs root SSH keys, disables SSH password login, and rotates root password to a strong random value.
- Rotated root password is saved inside the container at `/root/.coder-root-password` (mode `0600`) for break-glass console access.

Q: Does stopping a workspace delete the CT and disks?

- No. The CT now stays managed permanently and only toggles running state with Coder start/stop (`started = transition == "start"`).
- Root disk and optional `/home/coder` disk are kept across stop/start and host reboot.

Q: How do I keep user data when rebuilding/replacing a workspace container?

- Use `enable_home_disk = true` so `/home/coder` is a separate mount.
- Before replacement, note the existing home volume id (for example `local-lvm:subvol-<vmid>-disk-1`) and set `proxmox_home_volume_id` to reattach it.
