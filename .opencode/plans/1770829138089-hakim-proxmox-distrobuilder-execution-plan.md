# Hakim Proxmox + Distrobuilder Execution Plan

Date: 2026-02-11
Status: ready
Scope: add a new Proxmox LXC Coder template using Distrobuilder-generated golden templates, while keeping existing Docker template intact.

## Decisions Locked

- Option A is selected: prebaked golden LXC templates per variant.
- Template build system: Distrobuilder YAML.
- Coder substrate for new template: Proxmox LXC via `bpg/proxmox` provider.
- Existing Docker template remains available and unchanged.

## Naming and Artifact Contract

- Template artifact name: `hakim-<variant>-<release>-<arch>.tar.xz`
- Variants: `base`, `php`, `dotnet`, `js`, `rust`, `elixir`
- Required companion file: `sha256sums.txt`
- Publish target: CI artifact store or GitHub Release assets (pick one and keep immutable versioned assets)

## Phase 0 - Foundation Decisions

- [x] Select distro baseline for LXC templates (recommended: Ubuntu LTS or Debian stable)
- [x] Select release and architecture targets (minimum: `amd64`, optional `arm64`)
- [x] Freeze version source-of-truth policy (reuse versions from existing `devcontainers` where applicable)
- [x] Lock artifact publication location and retention policy

## Phase 1 - Distrobuilder Scaffold

- [x] Add `distrobuilder/hakim.yaml` as single declarative source using `variants` filters
- [x] Add `distrobuilder/scripts/build-variant.sh`
- [x] Add `distrobuilder/scripts/build-all.sh`
- [x] Add `distrobuilder/scripts/actions/post-unpack.sh`
- [x] Add `distrobuilder/scripts/actions/post-packages.sh`
- [x] Add `distrobuilder/scripts/actions/post-files.sh`
- [x] Add `distrobuilder/out/.gitkeep` (or equivalent directory bootstrap)
- [x] Update `.gitignore` to ignore `distrobuilder/out/` and temp build dirs

## Phase 2 - Base OS and Toolchain Parity

- [x] Port base behavior from `devcontainers/base/Dockerfile` into Distrobuilder (`packages`, `files`, `actions`)
- [x] Port Mise install and env behavior from `devcontainers/base/install-mise.sh`
- [x] Ensure `/etc/profile.d/mise.sh` parity for PATH/shims
- [x] Ensure default `coder` user creation and home directory conventions
- [x] Ensure shell/runtime essentials installed (git, curl, jq, ca-certificates, etc.)
- [x] Ensure compatibility with Proxmox LXC guest expectations

## Phase 3 - Variant Mapping

- [x] Add `base` variant sections in `distrobuilder/hakim.yaml`
- [x] Add `php` variant sections (php stack + composer/laravel parity)
- [x] Add `dotnet` variant sections (match versions currently used)
- [x] Add `js` variant sections (Node + Bun parity)
- [x] Add `rust` variant sections (match profile/version currently used)
- [x] Add `elixir` variant sections (Erlang + Elixir + Phoenix + pg tools parity)
- [x] Ensure each variant outputs a deterministic tarball filename

## Phase 4 - Local Build Validation

- [x] Validate distrobuilder prerequisites on build host
- [ ] Build one `base` template locally and verify output files
- [ ] Build all variants locally and verify all six artifacts
- [ ] Generate checksums and verify checksum pass
- [ ] Manual Proxmox smoke test: import/use template, create CT, start CT
- [ ] Validate tool presence and user environment in CT per variant

## Phase 5 - CI Pipeline for Golden Templates

- [x] Add workflow `.github/workflows/build-lxc-templates.yml`
- [x] Build matrix for six variants
- [x] Generate and publish `sha256sums.txt`
- [x] Publish template tarballs to chosen artifact target
- [x] Add hard fail checks for missing artifacts and checksum mismatches

## Phase 6 - New Coder Template (Proxmox)

- [x] Create `coder/templates/hakim-proxmox/main.tf`
- [x] Create `coder/templates/hakim-proxmox/README.md`
- [x] Create `coder/templates/hakim-proxmox/scripts/setup-git.sh` (reuse existing behavior)
- [x] Add providers: `coder/coder` and `bpg/proxmox`
- [x] Add Proxmox parameters: endpoint/token/node/pool/datastore/bridge/vlan
- [x] Add template source mapping parameter(s) for each variant artifact
- [x] Add `proxmox_virtual_environment_download_file` resources for `vztmpl` artifacts
- [x] Add `proxmox_virtual_environment_container` resource with secure defaults
- [x] Enable IP readiness (`wait_for_ip`) for bootstrap reliability
- [x] Implement SSH bootstrap to install/start Coder agent in container
- [x] Preserve existing substrate-agnostic UX and module wiring from `coder/templates/hakim/main.tf`

## Phase 7 - Security Defaults and Compliance Toggles

- [x] Default `unprivileged = true`
- [x] Default nesting disabled; expose explicit toggle
- [x] Add firewall/network placement parameters (bridge/VLAN/profile)
- [x] Add egress mode parameter (`open`, `restricted`, `airgapped`)
- [x] Keep Docker-in-LXC disabled by default
- [x] Keep secrets flow aligned with existing Vault module pattern

## Phase 8 - Terraform Quality Gates

- [x] Run `terraform fmt -recursive` in template paths
- [x] Run `terraform init` in `coder/templates/hakim-proxmox`
- [x] Run `terraform validate` in `coder/templates/hakim-proxmox`
- [x] Commit `.terraform.lock.hcl` for new template

## Phase 9 - End-to-End Functional Validation

- [ ] Add workflow `.github/workflows/proxmox-e2e-smoke.yml` for matrix smoke runs in GitHub Actions
- [ ] Create workspace with `hakim-proxmox` + `base` variant
- [ ] Confirm CT provisioning and stable IP acquisition
- [ ] Confirm Coder agent comes online
- [ ] Confirm Git setup path works
- [ ] Confirm OpenCode/OpenChamber/OpenClaw module startup path works
- [ ] Confirm app access paths (`coder_app`, previews, code-server) work
- [ ] Repeat smoke tests for all variants

## Phase 10 - Rollout and Coexistence

- [x] Keep `coder/templates/hakim` (Docker) unchanged with publishing path intact
- [x] Configure `coder/templates/hakim-proxmox` to publish in parallel
- [ ] Pilot with small user cohort and collect breakages by variant
- [ ] Fix parity/security gaps and then widen rollout

## Validation Matrix

### Distrobuilder Build

- Command: `distrobuilder build-lxc distrobuilder/hakim.yaml -o image.variant=<variant> distrobuilder/out/<variant>`
- Expectation: template tarball generated for each variant and checksum present

### Proxmox Template Availability

- Command: `pveam list <storage>` (or `pvesm list <storage> --content vztmpl`)
- Expectation: each `hakim-<variant>-...tar.xz` is visible in `vztmpl`

### Terraform Plan/Apply

- Command: `terraform init && terraform validate && terraform plan`
- Expectation: valid plan, template download resource references valid `vztmpl`, container resource resolves template id

### Coder Workspace Runtime

- Action: create workspace from `hakim-proxmox`
- Expectation: agent online, modules/apps available, selected variant tools present

## Risks and Mitigations

- Risk: build host privilege/tooling drift for distrobuilder
  - Mitigation: pin builder image/deps and run deterministic CI job
- Risk: variant parity drift between devcontainers and LXC templates
  - Mitigation: maintain shared version mapping table and parity checks per release
- Risk: template URL/storage id drift across Proxmox environments
  - Mitigation: parameterize storage/node/template source and enforce validation in terraform vars
- Risk: LXC constraints for Docker/nesting workflows
  - Mitigation: disable by default and document opt-in security impact

## Definition of Done

- [ ] Six golden templates built reproducibly via CI with checksums
- [ ] New `hakim-proxmox` Coder template validates and provisions successfully
- [ ] Coder agent and core modules/apps function on all variants
- [x] Security-first defaults are active
- [x] Existing Docker template remains operational and unchanged
