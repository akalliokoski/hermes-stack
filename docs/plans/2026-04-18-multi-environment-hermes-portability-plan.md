# Multi-Environment Hermes Portability Plan

> **For Hermes:** Use `software-development/subagent-driven-development` if executing this plan later.

**Goal:** Make Hermes and all Hermes profiles portable across the VPS, MacBook, and future machines while keeping Hermes explicitly aware of its current runtime environment, available tools, and the correct backup/import/sync/networking workflows for that environment.

**Architecture:** Separate *shared intent* from *machine-local runtime facts*. Keep durable cross-profile/profile-sharing assets in synced/shared locations, keep machine-specific service wiring in an environment manifest, and make Hermes inject a generated environment summary into each profile so it always knows where it is running and what is locally possible. Treat the VPS as the always-on service host for Dockerized support services, while allowing Hermes itself plus synced profile state/instructions/skills to run from any machine.

**Tech Stack:** Hermes profiles, shared SOUL files, shared skills, Hindsight with per-profile `bank_id`, Syncthing, Tailscale, Docker Compose on VPS, host-native Hermes installs, backup tarballs, Litestream, logical `pg_dump` for Hindsight.

---

## 1. Current State and Constraints

### What already exists
- `scripts/provision-profile.sh` already supports shared SOUL sources, shared skills, per-profile workspaces, and per-profile Hindsight `bank_id` values.
- `SETUP.md` already documents:
  - local/mac setup with native Hermes + local support stack
  - VPS setup with native Hermes + Dockerized support services
  - profile provisioning via `make add-profile` or `sudo provision-profile`
- Syncthing and Tailscale are already part of the VPS deployment.
- Hindsight backups already use logical `pg_dump`; `.hermes` state already has tarball + Litestream-based backup paths.

### Gaps to close
1. Hermes does **not yet have a canonical environment manifest** that says “I am on `vps` / `macbook` / `future-laptop`”.
2. Hermes does **not yet automatically inject a machine/runtime capability summary** into every profile.
3. Backup/import procedures are documented, but **not unified into a machine-portability workflow**.
4. Syncthing currently helps with shared files, but **the exact split between synced state vs machine-local secrets/runtime config is not formalized enough**.
5. The VPS is the fixed host for Dockerized services, but **other machines need first-class ways to discover and consume those services**.

---

## 2. Target Operating Model

### 2.1 Role split

#### VPS (`env_id=vps`)
- Canonical always-on service host.
- Runs Dockerized support services:
  - Hindsight
  - Firecrawl
  - backup jobs
  - Litestream
  - Syncthing
  - Audiobookshelf
- Runs Hermes natively for the default profile and any always-on gateway profiles.
- Exposes approved web UIs and APIs over Tailscale.
- Stores authoritative service backup archives.

#### MacBook (`env_id=macbook`)
- Primary interactive workstation.
- Can run Hermes natively with local profiles.
- May use local support services for development/testing, or point Hermes at VPS-hosted services over Tailscale.
- Receives synced shared assets via Syncthing.
- Can restore/import a profile from synced/backed-up state without depending on the VPS shell.

#### Future machines (`env_id=<machine-name>`)
- Follow the same pattern as MacBook.
- Native Hermes install.
- Environment manifest says whether the machine is:
  - fully local/self-contained
  - client-of-vps-services
  - or temporary/minimal.

### 2.2 State split

#### Shared across machines via Syncthing
These should be sync-friendly, human-readable, and mostly conflict-tolerant:
- shared wiki: `~/sync/wiki`
- shared SOUL sources: `~/.hermes/shared/soul/`
- shared skills: `~/.hermes/shared/skills/`
- profile overrides/templates/manifests
- exported profile metadata
- backup archives intended for portability/import

#### Machine-local and not blindly synced
These should stay local or be regenerated:
- `.env` secrets for the machine
- machine-local `config.yaml` overrides
- runtime service bindings and paths
- active logs, caches, cron output
- SQLite live DB files that already have their own replication/backup strategy
- host-specific systemd/Tailscale/Syncthing runtime config

#### Per-profile but portable
These should be reproducible on another machine from sync + restore/import steps:
- profile identity/config template
- rendered `SOUL.md`
- Hindsight `bank_id`
- workspace path mapping template
- profile-local env file template (without secrets committed into sync)

---

## 3. Core Design: Environment Awareness as Data

### 3.1 Add a canonical machine manifest
Create a shared machine-inventory directory, for example:

```text
~/sync/hermes/envs/
├── vps.yaml
├── macbook.yaml
└── <future-machine>.yaml
```

Each file should describe *declared* facts about that environment, for example:

```yaml
env_id: vps
role: service-host
hostname: vps
profile_root: /home/hermes/.hermes
work_root: /home/hermes/work
wiki_path: /home/hermes/sync/wiki
sync_root: /home/hermes/sync
services:
  hindsight:
    mode: local_docker
    api_url: http://127.0.0.1:8888
    ui_url: https://vps.taild96651.ts.net:9443/
  firecrawl:
    mode: local_docker
    api_url: http://127.0.0.1:3002
  syncthing:
    mode: local_docker
    gui_url: https://vps.taild96651.ts.net:9445/
  tailscale:
    mode: host_native
capabilities:
  can_manage_systemd: true
  can_manage_tailscale_serve: true
  can_run_docker_compose: true
  can_access_local_hindsight_container: true
notes:
  - Dockerized support services are hosted here.
```

And for the MacBook:

```yaml
env_id: macbook
role: workstation
hostname: <mac-hostname>
profile_root: ~/.hermes
work_root: ~/hermes-work
wiki_path: ~/Sync/hermes/wiki
sync_root: ~/Sync/hermes
services:
  hindsight:
    mode: remote_vps
    api_url: http://vps.tailnet-name.ts.net:8888   # or routed/proxied equivalent
  firecrawl:
    mode: remote_vps
  syncthing:
    mode: native_app_or_remote_gui
  tailscale:
    mode: host_native
capabilities:
  can_manage_systemd: false
  can_manage_launchd: true
  can_run_docker_compose: optional
  can_access_local_hindsight_container: false
notes:
  - Primary interactive workstation.
```

### 3.2 Generate a runtime capability summary
Add a script that combines:
- declared manifest facts
- live detection facts (`hostname`, `whoami`, OS, path existence, service reachability)

into a generated file such as:

```text
~/.hermes/ENVIRONMENT.md
```

This file should state:
- current environment ID and role
- current machine/hostname
- current profile root/work root/wiki path
- which local tools/services are actually available here
- which services are remote and how to access them
- what Hermes should and should not try to do on this machine

### 3.3 Inject environment awareness into every profile
Update `scripts/provision-profile.sh` (or a companion sync script) so every profile gets one of:
1. a rendered `ENVIRONMENT.md` included into `SOUL.md`, or
2. a profile-local generated block inside `SOUL.md`, or
3. a `prefill_messages_file` / similar context file if Hermes supports that cleanly.

The injected content should teach Hermes rules like:
- “You are currently running on `vps`.”
- “Tailscale Serve changes can only be done on the VPS host.”
- “On MacBook, use VPS-hosted Hindsight/Firecrawl unless local dev stack is explicitly enabled.”
- “Do not claim local Docker/systemd/Tailscale control when the capability summary says unavailable.”

### 3.4 Prefer capability-based behavior, not hostname guessing
Hermes should decide behavior from fields like:
- `can_manage_systemd`
- `can_run_docker_compose`
- `hindsight.mode`
- `tailscale.mode`

not from brittle assumptions like “if hostname contains vps then do X”.

---

## 4. Data Portability and Backup/Import Model

### 4.1 Define backup layers clearly
Use three layers, each with a different purpose.

#### Layer A — synced shared assets
Purpose: fast continuity across machines.
- Syncthing replicates wiki, shared SOUL, shared skills, machine manifests, and export/import bundles.
- This is the first thing a new machine receives.

#### Layer B — Hermes profile/state backups
Purpose: restore `.hermes` profile state.
- Keep existing tarball backups for `.hermes`.
- Keep Litestream snapshots for `state.db`.
- Document which pieces are restored from tarball vs SQLite snapshot.

#### Layer C — Hindsight logical dumps
Purpose: preserve/import semantic memory backend independently of `.hermes`.
- Keep `pg_dump`-based Hindsight dumps as the canonical Hindsight backup/export format.
- Store them under the Syncthing-backed backup path already used on the VPS.
- Add an equally canonical **import/restore** workflow to complement backup.

### 4.2 Add explicit import commands
The repo should provide first-class import/restore commands, not just raw scripts.

Recommended Make targets / scripts:

```bash
make backup-profile PROFILE=default
make export-profile PROFILE=default
make import-profile PROFILE=default ARCHIVE=...
make backup-hindsight
make restore-hindsight DUMP=...
make sync-env
make detect-env
```

#### `export-profile`
Creates a portable bundle containing:
- profile metadata/config
- rendered and source SOUL files
- shared skill references
- non-secret env template
- latest safe state snapshot reference
- optional Hindsight bank metadata reference

#### `import-profile`
Given a bundle on a new machine, it should:
- create/repair the Hermes profile
- restore profile config
- render SOUL
- map workspace for the current machine
- configure shared skills
- configure Hindsight for the right `bank_id`
- optionally restore/import Hindsight memory if requested

### 4.3 Add Hindsight import support
Current backup is stronger than restore ergonomics. Add a supported restore path such as:
- `scripts/restore-hindsight.sh`
- or `make restore-hindsight DUMP=...`

It should support at least:
1. restoring the whole Hindsight DB on the VPS service host
2. importing a named profile’s bank into the shared Hindsight service
3. validating that target `bank_id` exists and is non-empty after restore

### 4.4 Keep secrets out of Syncthing by default
Sync templates, not raw secrets.

Recommended pattern:
- sync `.env.example` or per-profile `.env.template`
- keep actual `.env` local to each machine
- provide `scripts/bootstrap-machine-env.sh` to materialize local `.env` from templates + manual secret entry

---

## 5. Syncthing Design for Multi-Machine Hermes

### 5.1 Sync the right roots
Use Syncthing for a machine-agnostic root such as:

```text
~/sync/hermes/
├── wiki/
├── envs/
├── exports/
├── backups/
├── soul/
└── skills/
```

Then make local Hermes paths reference this shared root where appropriate.

### 5.2 Stop syncing unstable runtime data directly
Avoid syncing hot runtime state that causes noise/conflicts or is better restored another way:
- SQLite live DBs
- session logs
- caches
- active cron output
- sockets, temp files
- host-specific service configs

The current ignore strategy is already moving in the right direction; formalize it as policy.

### 5.3 Add environment bootstrap from synced assets
A new machine setup should be:
1. install Hermes natively
2. install Tailscale + Syncthing
3. sync `~/sync/hermes`
4. run `make detect-env` or `scripts/bootstrap-machine.sh`
5. generate local `~/.hermes/config.yaml` from shared base + env manifest
6. run `make sync-profiles-local`
7. optionally import/restore profile state and Hindsight memory

---

## 6. Tailscale Design for Service Discovery and Reachability

### 6.1 Treat Tailscale as the cross-machine service fabric
The VPS remains the stable service host. Other machines consume services over Tailscale.

Use environment manifests to declare canonical endpoints, for example:
- Hindsight UI/API
- Firecrawl API
- Syncthing GUI
- Audiobookshelf
- Hermes dashboard

### 6.2 Standardize service endpoint names in the manifest
Every environment should know both:
- local endpoint if running locally
- remote fallback endpoint if provided by VPS

Example:

```yaml
services:
  hindsight:
    local_api_url: http://127.0.0.1:8888
    remote_api_url: http://vps.tailnet.ts.net:8888
    preferred_mode: remote_vps
```

Then generated environment context can say:
- “Use remote_vps hindsight from the MacBook.”
- “Use local_docker hindsight on the VPS.”

### 6.3 Keep Tailscale Serve config VPS-specific
Do **not** treat Tailscale Serve as universal across machines.
- On VPS: Hermes may manage Serve if capability says yes.
- On MacBook: Hermes should know those services are consumers, not published infra, unless explicitly configured otherwise.

---

## 7. Config Refactor Needed in Hermes Stack

### 7.1 Split config into shared base + environment overlays
Introduce something like:

```text
config/
├── base.yaml
├── env/
│   ├── vps.yaml
│   ├── macbook.yaml
│   └── <machine>.yaml
└── profiles/
    ├── default.yaml
    └── <profile>.yaml
```

Render final `~/.hermes/config.yaml` from:

```text
base + env/<machine> + profile/<name>
```

This is the config equivalent of the shared SOUL model you already adopted.

### 7.2 Move machine-specific paths out of the root canonical config
Today `config.yaml` still contains VPS-specific paths like `/home/hermes/work/default:/workspace` in the base config. That should become environment-rendered, not globally canonical.

Desired result:
- shared base config is machine-agnostic
- env overlay supplies `work_root`, terminal backend defaults, local service URLs
- profile provisioning only fills in profile-specific deltas

### 7.3 Add local profile sync command
Alongside current VPS profile sync, add a local equivalent, e.g.:

```bash
make sync-profiles-local
```

This should:
- detect current environment
- render local config for default + named profiles on this machine
- apply workspace mappings for this machine’s `work_root`
- write Hindsight config using local-vs-remote endpoint rules from the env manifest

---

## 8. Implementation Phases

## Phase 1 — Environment awareness foundation
**Outcome:** Hermes can reliably know where it is and what it can do.

1. Create shared env manifest schema under synced storage.
2. Add `scripts/detect-env.sh` or `scripts/render-environment-context.py`.
3. Generate `~/.hermes/ENVIRONMENT.md` from manifest + live checks.
4. Inject generated environment context into the default profile.
5. Extend `provision-profile.sh` to do the same for all profiles.
6. Add docs in `SETUP.md` for the env manifest workflow.

## Phase 2 — Config portability
**Outcome:** configs stop hardcoding VPS assumptions.

1. Introduce config base + environment overlay structure.
2. Render per-machine `config.yaml` instead of treating the repo root config as universal.
3. Add `make detect-env` and `make sync-profiles-local`.
4. Make workspace mappings derive from env manifest `work_root`.
5. Make Hindsight endpoint choice derive from env manifest service mode.

## Phase 3 — Backup/export/import completion
**Outcome:** any profile can be moved or reconstructed on another machine.

1. Add `export-profile` bundle format.
2. Add `import-profile` restore path.
3. Add `restore-hindsight` command.
4. Add validation commands for `bank_id`, tarball integrity, and profile render status.
5. Ensure export/import artifacts land in Syncthing-backed storage.

## Phase 4 — Syncthing/Tailscale operational polish
**Outcome:** cross-machine usage is ergonomic.

1. Formalize the Syncthing folder layout and ignore policy.
2. Add machine bootstrap script for fresh installs.
3. Standardize Tailscale service endpoint records in env manifests.
4. Add a status command that reports reachable local/remote services.

---

## 9. Concrete Deliverables to Add to the Repo

### New files/scripts
- `docs/plans/2026-04-18-multi-environment-hermes-portability-plan.md`
- `config/base.yaml`
- `config/env/vps.yaml`
- `config/env/macbook.yaml`
- `scripts/detect-env.sh`
- `scripts/render-environment-context.py`
- `scripts/render-config.py`
- `scripts/bootstrap-machine.sh`
- `scripts/export-profile.sh`
- `scripts/import-profile.sh`
- `scripts/restore-hindsight.sh`

### Make targets
- `make detect-env`
- `make sync-env`
- `make sync-profiles-local`
- `make export-profile PROFILE=<name>`
- `make import-profile PROFILE=<name> ARCHIVE=...`
- `make backup-hindsight`
- `make restore-hindsight DUMP=...`
- `make machine-bootstrap`

### Documentation updates
- expand `SETUP.md` with:
  - environment manifest design
  - MacBook-vs-VPS behavior rules
  - portable profile import/export flows
  - exact Syncthing folder contract
  - exact Tailscale service discovery contract

---

## 10. Acceptance Criteria

This project is complete when all of the following are true:

1. On any machine, Hermes can state:
   - which environment it is in
   - which local tools are available
   - which services are local vs remote
   - which actions it should avoid on this machine
2. A new machine can install Hermes, sync shared assets, run bootstrap, and get working profiles without manual file surgery.
3. Profiles keep shared instructions/skills but isolated Hindsight memory via stable `bank_id` values.
4. Hindsight backup **and restore/import** are both first-class, documented commands.
5. Syncthing is used for sync-friendly assets and archives, not as a fragile substitute for proper database restore.
6. Tailscale provides stable service reachability across machines without Hermes guessing URLs ad hoc.
7. The repo’s canonical config no longer assumes it only runs on `/home/hermes/...` on the VPS.

---

## 11. Recommended Execution Order

If implementing soon, do it in this order:

1. **Environment manifest + ENVIRONMENT.md generation**
2. **Inject environment context into profiles**
3. **Config overlay rendering (base + env + profile)**
4. **Local sync command for MacBook/other machines**
5. **Profile export/import commands**
6. **Hindsight restore/import command**
7. **SETUP.md rewrite for the new operating model**

This order gives Hermes environment awareness first, then portability, then polished restore flows.

---

## 12. Key Decision Summary

- Keep Dockerized support services primarily on the VPS.
- Let Hermes run natively on any machine.
- Sync shared intent/assets with Syncthing.
- Keep machine-local secrets and runtime config local.
- Preserve per-profile Hindsight isolation with stable `bank_id` naming.
- Add explicit environment manifests so Hermes knows where it is.
- Add explicit export/import/restore commands so portability is operational, not aspirational.
