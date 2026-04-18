# Hermes — Setup & Operations

This document covers the deployment layer: local dev, VPS setup, configuration, day-to-day ops, state, and backup/restore.

**Topology.** `hermes-agent` runs natively on the VPS under systemd (user: `hermes`), installed via the upstream [install.sh](https://hermes-agent.nousresearch.com/docs/getting-started/installation). Shell tool calls are sandboxed inside fresh Docker containers via hermes's [Docker terminal backend](https://hermes-agent.nousresearch.com/docs/user-guide/docker). Docker Compose only runs the auxiliary services: firecrawl, hindsight, litestream, backup, and (on VPS) syncthing.

---

## Stack Overview

```
VPS host
├── systemd: hermes-gateway.service          (user: hermes)
│     └── hermes gateway run                 (state in /home/hermes/.hermes)
│           └── docker run nikolaik/... per shell command (terminal backend)
│
└── docker compose
      ├── firecrawl-api  + firecrawl-worker  127.0.0.1:3002 (web scraping)
      ├── playwright, redis, db, rabbitmq, nuq-migrate
      ├── hindsight                          127.0.0.1:8888 / 9999 (vector memory)
      ├── litestream                         continuous state.db WAL replication
      ├── backup                             daily /home/hermes/.hermes tarball
      └── syncthing (VPS only)               sync /home/hermes/.hermes → MacBook
                                             over Tailscale
```

**Compose files:**

| File | Purpose |
|---|---|
| `docker-compose.yml` | Base — auxiliary services only |
| `docker-compose.override.yml` | Local dev overrides (auto-applied) |
| `docker-compose.vps.yml` | VPS additions: syncthing, host backup bind-mount |

---

## Prerequisites

- Docker + Docker Compose v2
- `make`, `rsync`, `ssh`
- VPS: Tailscale on both VPS and MacBook (authenticated)

---

## Local Dev (MacBook)

By default, the MacBook profile setup is treated as a **workstation that consumes VPS-hosted services over Tailscale**. The local docker-compose stack remains available as an optional dev/test mode when you explicitly want local Firecrawl/Hindsight containers.

### First run

```bash
# 1. Install hermes natively (one-time)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
exec $SHELL   # reload PATH

# 2. Seed config + secrets
cp .env.example .env        # fill in API keys, TELEGRAM_BOT_TOKEN, VPS_HOST, …
cp .env        ~/.hermes/.env

# 3. Bootstrap the machine-specific shared/synced layout + render config
make machine-bootstrap

# 4. Optional: start the local support stack (firecrawl, hindsight, litestream, backup)
make local-up SERVICE_MODE=local

# 5. Verify what Hermes believes is available here
make verify-env-local

# 6. Chat with hermes
make local-chat
```

Hermes is talking to Docker for each shell tool call — confirm with `docker ps` during a command (you'll see a short-lived `nikolaik/python-nodejs` container).

### Updating hermes

```bash
make local-update-agent    # runs `hermes update`
```

### Common commands

```bash
make local-up SERVICE_MODE=local   # start local support services and prefer local APIs
make local-down                    # stop them
make local-status                  # compose ps
make local-logs                    # tail all compose logs
make detect-env                    # print detected environment id (vps/macbook/...)
make machine-bootstrap             # create synced layout + shared symlinks + render config
make sync-env                      # rerender ~/.hermes/config.yaml + ~/.hermes/ENVIRONMENT.md
make sync-profiles-local           # normalize default + named profiles for this machine
make verify-env-local              # validate rendered profile wiring for this machine
make sync-profiles-local SERVICE_MODE=local   # opt into local Hindsight URLs when running local dev containers
make export-profile PROFILE=default           # create portable profile bundle under synced exports root
make import-profile ARCHIVE=/path/to/bundle.tar.gz PROFILE=default
make local-chat                    # hermes chat
make local-backup-now              # trigger immediate backup
make local-snapshots               # list available backups
```

### Config

The canonical config source is now split into:

- `config/base.yaml`
- `config/env/vps.yaml`
- `config/env/macbook.yaml`

Render the config for the current machine with:

```bash
make sync-env
```

That writes:

- `~/.hermes/config.yaml`
- `~/.hermes/ENVIRONMENT.md`

The generated environment file is also injected into profile `SOUL.md` renders so Hermes knows which machine it is running on, which local capabilities exist, and which services are remote.

If PyYAML is missing, the local `make sync-*` and `make local-setup-hindsight` targets bootstrap it automatically via `scripts/ensure-python-yaml.sh`.

Key fields:

```yaml
model:
  default: google/gemma-4-26b-a4b-it
  provider: openrouter
  base_url: https://openrouter.ai/api/v1

terminal:
  backend: docker                             # sandbox each command
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  docker_volumes:
    - /home/hermes/work/default:/workspace    # only writable path inside the sandbox
  cwd: /workspace

approvals:
  mode: manual                                # dangerous commands require chat approval
```

Each profile gets its own subdirectory under `/home/hermes/work/` mounted as `/workspace` inside its container. On the MacBook, change `/home/hermes/work/default` to a local path (e.g. `$HOME/hermes-work/default`).

---

## VPS Deployment

### One-time bootstrap

Run [scripts/vps-bootstrap.sh](scripts/vps-bootstrap.sh) from the MacBook. It reads `VPS_HOST` from `.env`, prompts for confirmation (the step is destructive on an existing VPS), and then:

1. Stages `vps-reset.sh`, `vps-setup.sh`, `hermes-gateway.service`, repo config overlays, and `.env` into `/tmp/hermes-bootstrap/` on the VPS.
2. Runs [scripts/vps-reset.sh](scripts/vps-reset.sh) — stops the hermes-gateway unit, `docker compose down --volumes` on the old stack, removes the `hermes_*` named volumes, wipes `/opt/hermes-backups` and `/home/hermes/{.hermes,work}`. Safe no-op on a clean VPS.
3. Runs [scripts/vps-setup.sh](scripts/vps-setup.sh) — installs Docker (if missing), creates the `hermes` system user, adds it to the `docker` group, installs hermes-agent via the upstream install.sh, seeds `/home/hermes/.hermes/.env`, renders `/home/hermes/.hermes/config.yaml` from the `vps` environment overlay, creates `/opt/hermes-backups` + `/opt/hermes`, installs and enables the `hermes-gateway` systemd unit (but does not start it).
4. Cleans up the staged files.

```bash
bash scripts/vps-bootstrap.sh     # one-time, from MacBook
git push                           # subsequent deploys go through CI
```

After bootstrap, the first `git push` to `main` (or a manual `make deploy`) rsyncs the repo, renders the latest VPS config, syncs all profiles/environment context, brings up the support stack, and `systemctl restart hermes-gateway` starts the agent for the first time.

`VPS_HOST` and `VPS_DIR` are read from `.env`:

```bash
VPS_HOST=my-vps           # Tailscale hostname or IP
VPS_DIR=/opt/hermes       # default
```

The individual scripts can also be run standalone (e.g. `ssh $VPS_HOST 'sudo bash -s' < scripts/vps-setup.sh`) if you want to skip the wipe on a fresh VPS.

### Deploying updates

```bash
make deploy          # rsync repo, docker compose up -d, systemctl restart hermes-gateway
make update-agent    # bumps hermes to latest (runs `hermes update` on VPS)
```

Hermes no longer lives as a git submodule — new releases are pulled by `hermes update`, not by rebuilding a container.

### `hermes` wrapper script (VPS root sessions)

The `hermes` binary is installed under the `hermes` user. Running it as root (e.g. for system gateway installs) is verbose without a wrapper. Install once on the VPS:

```bash
cat > /usr/local/bin/hermes << 'EOF'
#!/bin/bash
HERMES_BIN=$(sudo -iu hermes which hermes)
export HERMES_HOME=/home/hermes/.hermes
if [[ "$*" == *"--system"* ]]; then
    exec "$HERMES_BIN" "$@"
else
    exec sudo -iu hermes "$HERMES_BIN" "$@"
fi
EOF
chmod +x /usr/local/bin/hermes
```

- Commands **without** `--system` run as the `hermes` user (correct `HERMES_HOME`).
- Commands **with** `--system` run as root (required for writing to `/etc/systemd/system/`).
- `HERMES_HOME` is always set to `/home/hermes/.hermes` so root doesn't fall back to `/root/.hermes`.

### Adding a new profile + gateway

The repo now has one canonical provisioning script that works both ways:

```bash
# From MacBook
make add-profile PROFILE=<name>
make add-profile PROFILE=<name> TELEGRAM_BOT_TOKEN=***
make sync-souls
make sync-profiles

# Directly on the VPS (including from Hermes chat)
cd /opt/hermes
sudo bash scripts/provision-profile.sh --profile <name>
sudo bash scripts/provision-profile.sh --profile <name> --telegram-bot-token ***
sudo bash scripts/provision-profile.sh --sync-all-profiles --gateway skip

# Short helper command installed by vps-setup.sh:
sudo provision-profile <name>
sudo provision-profile <name> ***
```

`scripts/provision-profile.sh`:

- creates `/home/hermes/work/<name>`
- creates the Hermes profile if needed
- updates `docker_volumes` to mount the profile-specific workspace at `/workspace`
- optionally writes `TELEGRAM_BOT_TOKEN` to the profile's `.env`
- writes `<user-home>/.config/git/shared.gitconfig` into the profile-local git include path so local and VPS installs both use the correct shared git defaults
- writes `/home/hermes/.hermes/profiles/<name>/hindsight/config.json` in the current Hermes Hindsight plugin format (`mode: local_external`, `api_url`, `bank_id`, auto-retain/recall settings)
- renders `SOUL.md` from shared base + per-profile override
- installs + starts the system gateway when root (or passwordless sudo) is available

If you edit shared instructions later, rerender all profile `SOUL.md` files with:

```bash
make sync-souls
# or directly on the VPS:
sudo bash /opt/hermes/scripts/provision-profile.sh --sync-all-souls
# or via the helper:
sudo provision-profile --sync-all
```

If you need to repair or normalize profile-local git/Hindsight/SOUL config for the default profile and every named profile, run:

```bash
make sync-profiles
# or directly on the VPS:
sudo bash /opt/hermes/scripts/provision-profile.sh --sync-all-profiles --gateway skip
```

### Shared instructions across profiles

Common instructions still render through `~/.hermes/shared/soul/`, but `make machine-bootstrap` now links that directory to the Syncthing-backed shared root when possible:

```text
~/.hermes/shared/soul -> <sync_root>/soul
~/.hermes/shared/skills -> <sync_root>/skills
```

Within the synced root, the contract is:

```text
<sync_root>/
├── wiki/
├── soul/
│   ├── base.md
│   └── profiles/
│       ├── default.md
│       └── <name>.md
├── skills/
├── exports/
├── backups/
│   └── hindsight/
└── envs/
```

Each profile `SOUL.md` is rendered as:

```text
shared/soul/base.md + shared/soul/profiles/<name>.md + profile ENVIRONMENT.md
```

This gives you one place for common behavior, while keeping profile-specific instructions separate and synced across machines. Hindsight memory remains isolated per profile because each profile still gets its own `bank_id` even though all profiles use the same Hindsight service.

### Environment manifests and runtime awareness

Hermes environment-awareness is driven by repo-managed manifests plus a generated runtime summary:

```text
config/
├── base.yaml
└── env/
    ├── vps.yaml
    └── macbook.yaml
```

The operating flow is:

- `scripts/detect-env.sh` picks the current environment id.
- `scripts/render-config.py` renders a machine-specific `config.yaml`.
- `scripts/render-environment-context.py` generates `ENVIRONMENT.md`, including the preferred service URLs for the chosen `SERVICE_MODE`.
- `scripts/provision-profile.sh` regenerates profile `config.yaml`, `ENVIRONMENT.md`, and `SOUL.md` together.
- `scripts/verify-environment.sh` validates that rendered profiles match the declared environment contract.
- `scripts/bootstrap-machine.sh` creates the synced/shared directory layout, mirrors env manifests into `<sync_root>/envs`, links shared soul/skills, and rerenders local profiles.

On a local machine, run:

```bash
make detect-env
make machine-bootstrap SERVICE_MODE=remote
make verify-env-local SERVICE_MODE=remote
```

If you intentionally want local support services on a workstation:

```bash
make local-up SERVICE_MODE=local
make machine-bootstrap SERVICE_MODE=local
make verify-env-local SERVICE_MODE=local
```

On the VPS, deploy or run:

```bash
sudo env HERMES_ENV_ID=vps HERMES_SERVICE_MODE=auto bash scripts/provision-profile.sh --sync-all-profiles --gateway skip
sudo -iu hermes HERMES_HOME=/home/hermes/.hermes bash scripts/verify-environment.sh --all-profiles --check-services
```

### VPS-specific services

**Syncthing** now synchronizes the machine-agnostic shared root at `/home/hermes/sync`, not the entire live `~/.hermes` runtime directory. The important split is:

- synced: `wiki/`, shared `soul/`, shared `skills/`, `exports/`, backup archives, copied env manifests
- not blindly synced: `~/.hermes/.env`, live `state.db*`, sessions/logs/cron caches, platform auth, host-specific runtime config

Open the Hermes stack landing page from any tailnet device:

```text
https://<current-tailscale-node-name>.<your-tailnet>.ts.net/
```

That landing page links to the Hermes dashboard, Syncthing UI, Hindsight UI/API, Firecrawl API, and Audiobookshelf. Direct paths are also available:

- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9444/` (Hermes Dashboard)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9445/` (Syncthing UI)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:13378/` (Audiobookshelf UI/API)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9443/` (Hindsight UI)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net/memory/` (Hindsight API)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net/firecrawl/` (Firecrawl API)

All of these stay bound to `127.0.0.1` on the VPS and are published externally only through the host Tailscale daemon. The deploy flow reapplies `scripts/configure-tailscale-serve.sh` and verifies the live Serve listeners against the node's current MagicDNS/cert domain so hostname drift fails deployment instead of leaving stale URLs behind.

Point the MacBook side at `~/Sync/hermes` (or wherever). Obsidian → **Open folder as vault** → `~/Sync/hermes/wiki`.

#### Syncthing settings to change after first deploy (one-time)

Because the shared root now lives directly at `/home/hermes/sync`, do the following in the Syncthing UI after first start or after migrating from the old layout:

1. **Remove** the old `hermes-data` and `shared` folders (Edit → Remove; keep files on disk).
2. **Add** a new folder:
   - Folder Path (in container): `/sync`
   - Folder ID: `hermes`
   - Share with the MacBook device.
3. On the **MacBook**: accept the share, point it at `~/Sync/hermes` (or your chosen path).
4. Enable **Staggered File Versioning** (30 days, 1 h interval) on the new folder.
5. Once initial sync is done, reopen Obsidian at the synced vault path (`~/Sync/hermes/wiki`).
6. Run `make machine-bootstrap` on the MacBook so `~/.hermes/shared/{soul,skills}` link into the synced tree and local config is rerendered.

**Tailscale** exposes the landing page and all internal web UIs on your tailnet via the host Tailscale daemon (not a container). Deploy applies this automatically with:

```bash
sudo bash scripts/configure-tailscale-serve.sh
```

### Podcast pipeline helpers

Deploy also installs a dedicated podcast pipeline venv for Hermes under:

```text
/home/hermes/.venvs/podcast-pipeline/bin/python
```

That venv contains validated dependencies for:
- `podcastfy==0.4.3`
- `playwright` (Python package)
- `mutagen`

The main orchestration entrypoint is:

```bash
python3 /opt/hermes/scripts/make-podcast.py --title "AI Research Weekly" --source-file /path/to/notes.md --kokoro-base-url http://mac.tailnet.ts.net:8880/v1 --dry-run
```

Required env/config for a real run:
- `KOKORO_BASE_URL` or `--kokoro-base-url`
- `AUDIOBOOKSHELF_BASE_URL` optional (defaults to `http://127.0.0.1:13378`)
- optional `TELEGRAM_BOT_TOKEN` + `TELEGRAM_HOME_CHANNEL` for ready notifications

The script can:
- ask Hermes to generate the transcript from local files, URLs, inline text, or a topic hint
- call the shared `podcast-pipeline` skill wrappers
- write the MP3 into `/data/audiobookshelf/podcasts/ai-generated/`
- trigger an Audiobookshelf scan
- send a Telegram notification when configured

---

## Environment variables

See [.env.example](.env.example) for the authoritative, commented list. Highlights:

- `OPENROUTER_API_KEY` (or `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`) — LLM provider.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (numeric IDs, from @userinfobot), `TELEGRAM_HOME_CHANNEL`.
- `FIRECRAWL_API_URL=http://127.0.0.1:3002`, `HINDSIGHT_API_URL=http://127.0.0.1:8888`, `AUDIOBOOKSHELF_BASE_URL=http://127.0.0.1:13378`.
- `KOKORO_BASE_URL=http://<mac-tailnet-name>.ts.net:8880/v1`, `PODCASTFY_PYTHON=/home/hermes/.venvs/podcast-pipeline/bin/python`, `PODCAST_OUTPUT_DIR=/data/audiobookshelf/podcasts/ai-generated`.
- `VPS_HOST`, `VPS_DIR` (deploy).
- `HERMES_DATA_DIR` — overrides the bind-mount source for litestream/backup (default `/home/hermes/.hermes`; use `~/.hermes` locally).

---

## Agent state & persistence

Everything live/runtime-specific stays under `/home/hermes/.hermes` (VPS) / `~/.hermes` (MacBook), while the machine-agnostic shared root lives under `/home/hermes/sync` (VPS) / `~/Sync/hermes` (MacBook).

```text
.hermes/
├── config.yaml               ← rendered from config/base.yaml + config/env/<env>.yaml
├── ENVIRONMENT.md            ← generated machine/runtime capability summary
├── .env                      ← secrets (NOT synced)
├── state.db + wal            ← replicated by Litestream (NOT synced)
├── memories/                 local runtime state
├── SOUL.md                   rendered from shared soul + ENVIRONMENT.md
├── shared/
│   ├── soul -> <sync_root>/soul
│   └── skills -> <sync_root>/skills
├── sessions/ logs/ cron/     runtime-only, not synced
└── platforms/                platform auth (WhatsApp/Signal), not synced

<sync_root>/
├── wiki/                     synced Obsidian vault
├── soul/                     shared profile instructions
├── skills/                   shared cross-profile skills
├── exports/                  portable profile bundles
├── backups/                  tarballs + hindsight SQL dumps
└── envs/                     mirrored environment manifests
```

Each profile has its own subdirectory under `/home/hermes/work/` or `~/hermes-work/` bind-mounted into the Docker sandbox as `/workspace`. New profiles are added with `make add-profile PROFILE=<name>` on the VPS or imported locally via `make import-profile ARCHIVE=... PROFILE=<name>`.

---

## Backup & Restore

Three complementary layers protect portability and recovery:

### 1. Litestream (continuous SQLite replication)

`state.db` is a live WAL-mode SQLite DB — it cannot be safely `tar`'d while running. Litestream streams WAL pages to the backup archive every 10–30 s and writes full snapshots every 6–12 h.

```bash
make snapshots                                  # list restore points
make restore ARGS="db latest"                   # roll state.db back
make restore ARGS="db 2026-04-05T21:00:00"      # point-in-time restore
```

### 2. docker-volume-backup tarballs (`.hermes` runtime state)

Every day at 3am on VPS (weekly locally), the runtime `.hermes` dir is tarballed into the synced backup root.

```bash
make backup-now
make local-backup-now
make restore ARGS="volume hermes_data_2026-04-05T03-00-00.tar.gz"
make restore ARGS="file memories/MEMORY.md hermes_data_2026-04-05T03-00-00.tar.gz"
```

### 3. Hindsight logical SQL dumps

The VPS backup flow also writes a logical `pg_dump` snapshot of Hindsight into `backups/hindsight/`, keeping Hindsight protected independently of live Docker volumes.

```bash
make backup-hindsight
make restore-hindsight ARGS="list"
make restore-hindsight ARGS="validate-bank hermes-default"
make restore-hindsight ARGS="restore-db /home/hermes/sync/backups/hindsight/hindsight_dump_....sql"
```

### Portable profile export/import

Use exports when you want to move a profile to another machine without hand-editing config paths.

```bash
make export-profile PROFILE=default
make import-profile PROFILE=default ARCHIVE=~/Sync/hermes/exports/profiles/default/default_macbook_....tar.gz
```

`export-profile` writes a portable bundle containing:

- profile metadata (`bank_id`, source env, service mode)
- rendered `SOUL.md` / `ENVIRONMENT.md` / config references
- shared soul source files relevant to the profile
- `.env.template` without secret values
- references to the latest synced tarball + Hindsight dump

`import-profile` restores shared/profile soul sources, rerenders the profile for the target machine, and keeps reference copies of the source-machine artifacts under `~/.hermes[/profiles/<name>]/imports/`.

**Backup locations:**

| Env | Sync root | Tarballs | Hindsight SQL dumps |
|---|---|---|---|
| Local | `~/Sync/hermes` (recommended) | `<sync_root>/backups/*.tar.gz` | `<sync_root>/backups/hindsight/*.sql` |
| VPS | `/home/hermes/sync` | `/home/hermes/sync/backups/*.tar.gz` | `/home/hermes/sync/backups/hindsight/*.sql` |

---

## CI/CD (GitHub Actions)

`.github/workflows/deploy.yml` still runs on push to `main`: joins tailnet → rsync → `docker compose up -d` → `systemctl restart hermes-gateway`. Secrets unchanged (`VPS_HOST`, `VPS_SSH_*`, `TAILSCALE_OAUTH_*`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_HOME_CHANNEL`). The old "build hermes-agent image" step is gone.

---

## All `make` targets

### VPS

| Target | Description |
|---|---|
| `make up` | Start support services |
| `make down` | Stop support services |
| `make deploy` | Push + redeploy from MacBook |
| `make status` | Gateway unit + compose ps |
| `make logs` | `journalctl -u hermes-gateway -f` |
| `make logs-all` | Compose logs |
| `make restart` | Restart `hermes-gateway` |
| `make chat` | `hermes chat` as the hermes user |
| `make shell` | Bash shell as the hermes user |
| `make hermes ARGS="skills"` | Arbitrary hermes subcommand |
| `make update-agent` | `hermes update` + restart |
| `make backup-now` | Immediate tarball |
| `make backup-hindsight` | Trigger a logical Hindsight SQL dump on the VPS |
| `make snapshots` | List restore points |
| `make restore ARGS="..."` | See Backup & Restore |
| `make restore-hindsight ARGS="..."` | Validate or restore Hindsight SQL dumps on the VPS |
| `make verify-env` | Verify rendered VPS profile/environment wiring and service reachability |
| `make clean` | Prune stopped containers + dangling images |
| `make add-profile PROFILE=name` or `make add-profile PROFILE=name TELEGRAM_BOT_TOKEN=***` | Create/update a profile with its own workspace, SOUL override, Hindsight bank, and optional Telegram bot |
| `make sync-souls` | Rerender `SOUL.md` for default + all named profiles from shared sources |

### Local dev

| Target | Description |
|---|---|
| `make local-up` / `local-down` | Support services |
| `make local-status` / `local-logs` | Observability |
| `make machine-bootstrap` | Create synced shared layout + render local config |
| `make verify-env-local` | Validate local rendered environment/profile wiring |
| `make local-chat` | `hermes chat` against `~/.hermes` |
| `make local-update-agent` | `hermes update` locally |
| `make export-profile PROFILE=name` | Create a portable profile bundle |
| `make import-profile PROFILE=name ARCHIVE=/path/to/bundle.tar.gz` | Import a portable profile bundle locally |
| `make local-backup-now` / `local-snapshots` | Backups |
| `make portability-smoke` | Run local regression/smoke checks for portability scripts |

---

## Troubleshooting

**`docker: permission denied` from inside hermes (Docker terminal backend failing)**
The `hermes` user isn't in the `docker` group yet, or the current shell session pre-dates the group change. Re-run `sudo usermod -aG docker hermes` and restart the unit: `sudo systemctl restart hermes-gateway`.

**firecrawl-api keeps restarting**
`nuq-migrate` didn't complete. Check `docker compose logs nuq-migrate`.

**state.db missing after a wipe**
`make restore ARGS="db latest"` before restarting the gateway.

**Telegram warning: "fallback IPs active: 149.154.167.220"**
Normal — hermes's own fallback transport arming itself. Gateway is connected.

**Syncthing not syncing**
Check the tailnet UI at `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9445/`. Verify the MacBook device is approved and the `hermes` folder is shared in both directions.
