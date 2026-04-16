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

### First run

```bash
# 1. Install hermes natively (one-time)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
exec $SHELL   # reload PATH

# 2. Seed config + secrets
cp .env.example .env        # fill in API keys, TELEGRAM_BOT_TOKEN, VPS_HOST, …
cp config.yaml ~/.hermes/config.yaml
cp .env        ~/.hermes/.env

# 3. Start the support stack (firecrawl, hindsight, litestream, backup)
make local-up

# 4. Chat with hermes
make local-chat            # just runs `hermes chat`
```

Hermes is talking to Docker for each shell tool call — confirm with `docker ps` during a command (you'll see a short-lived `nikolaik/python-nodejs` container).

### Updating hermes

```bash
make local-update-agent    # runs `hermes update`
```

### Common commands

```bash
make local-up              # start support services
make local-down            # stop them
make local-status          # compose ps
make local-logs            # tail all compose logs
make local-chat            # hermes chat
make local-backup-now      # trigger immediate backup
make local-snapshots       # list available backups
```

### Config

`config.yaml` at the repo root is the canonical source; `make local-up`/first-run copies it to `~/.hermes/config.yaml`. Edit either location and re-copy, or symlink:

```bash
ln -sf "$PWD/config.yaml" ~/.hermes/config.yaml
```

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

1. Stages `vps-reset.sh`, `vps-setup.sh`, `hermes-gateway.service`, `config.yaml`, `.env` into `/tmp/hermes-bootstrap/` on the VPS.
2. Runs [scripts/vps-reset.sh](scripts/vps-reset.sh) — stops the hermes-gateway unit, `docker compose down --volumes` on the old stack, removes the `hermes_*` named volumes, wipes `/opt/hermes-backups` and `/home/hermes/{.hermes,work}`. Safe no-op on a clean VPS.
3. Runs [scripts/vps-setup.sh](scripts/vps-setup.sh) — installs Docker (if missing), creates the `hermes` system user, adds it to the `docker` group, installs hermes-agent via the upstream install.sh, seeds `/home/hermes/.hermes/{config.yaml,.env}`, creates `/opt/hermes-backups` + `/opt/hermes`, installs and enables the `hermes-gateway` systemd unit (but does not start it).
4. Cleans up the staged files.

```bash
bash scripts/vps-bootstrap.sh     # one-time, from MacBook
git push                           # subsequent deploys go through CI
```

After bootstrap, the first `git push` to `main` (or a manual `make deploy`) rsyncs the compose files, brings up the support stack, installs the latest `config.yaml`, and `systemctl restart hermes-gateway` starts the agent for the first time.

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
# From MacBook:
make add-profile PROFILE=<name>
make add-profile PROFILE=<name> TELEGRAM_BOT_TOKEN=***

# Directly on the VPS (including from Hermes chat via terminal tool):
cd /opt/hermes
sudo bash scripts/provision-profile.sh --profile <name>
sudo bash scripts/provision-profile.sh --profile <name> --telegram-bot-token ***

# Short helper command installed by vps-setup.sh:
sudo provision-profile <name>
sudo provision-profile <name> ***
```

`scripts/provision-profile.sh`:

- creates `/home/hermes/work/<name>`
- creates the Hermes profile if needed
- updates `docker_volumes` to mount the profile-specific workspace at `/workspace`
- optionally writes `TELEGRAM_BOT_TOKEN` to the profile's `.env`
- writes `/home/hermes/.hermes/profiles/<name>/home/.gitconfig` to include `/home/hermes/.config/git/shared.gitconfig`
- writes `/home/hermes/.hermes/profiles/<name>/hindsight/config.json` with `bankId: hermes-<name>`
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

### Shared instructions across profiles

Common instructions now live outside individual profile dirs:

```text
/home/hermes/.hermes/shared/soul/
├── base.md                 # shared by every profile
├── README.md
└── profiles/
    ├── default.md          # default profile only
    ├── coder.md            # coder profile only
    └── <name>.md
```

Each profile `SOUL.md` is rendered as:

```text
shared/soul/base.md + shared/soul/profiles/<name>.md
```

This gives you one place for common behavior, while keeping profile-specific instructions separate. Hindsight memory remains isolated per profile because each profile still gets its own `bankId` even though all profiles use the same Hindsight service.

### VPS-specific services

**Syncthing** mounts `/home/hermes/.hermes` as a single folder and syncs it to your MacBook over Tailscale. Files ignored by [docker/stignore](docker/stignore): `state.db*` (Litestream owns those), `sessions/`, `logs/`, `cron/`, `caches/`, `platforms/`, `.env`. Everything else — `memories/`, `SOUL.md`, `skills/`, `wiki/` — is synced.

Open the Hermes stack landing page from any tailnet device:

```text
https://openclaw-vps.taild96651.ts.net/
```

That landing page links to the Hermes dashboard, Syncthing UI, Hindsight UI/API, and Firecrawl API. Direct paths are also available:

- `https://openclaw-vps.taild96651.ts.net/dashboard/`
- `https://openclaw-vps.taild96651.ts.net/syncthing/`
- `https://openclaw-vps.taild96651.ts.net:9443/` (Hindsight UI)
- `https://openclaw-vps.taild96651.ts.net/memory/` (Hindsight API)
- `https://openclaw-vps.taild96651.ts.net/firecrawl/` (Firecrawl API)

All of these stay bound to `127.0.0.1` on the VPS and are published externally only through the host Tailscale daemon.

Point the MacBook side at `~/Sync/hermes` (or wherever). Obsidian → **Open folder as vault** → `~/Sync/hermes/wiki`.

#### Syncthing settings to change after first deploy (one-time)

Because this is a reshape of the old two-folder layout (`hermes-data` + `shared`), do the following in the Syncthing UI after first start:

1. **Remove** the old `hermes-data` and `shared` folders (Edit → Remove; keep files on disk).
2. **Add** a new folder:
   - Folder Path (in container): `/sync/hermes`
   - Folder ID: `hermes`
   - Ignore Patterns: already loaded from the bind-mounted `/sync/hermes/.stignore`.
   - Share with the MacBook device.
3. On the **MacBook**: accept the share, point it at `~/Sync/hermes` (or your chosen path).
4. Enable **Staggered File Versioning** (30 days, 1 h interval) on the new folder.
5. Once initial sync is done, delete the old `hermes-data` and `shared` copies on the MacBook.
6. Re-open Obsidian at the new vault path (`~/Sync/hermes/wiki`).

**Tailscale** exposes the landing page and all internal web UIs on your tailnet via the host Tailscale daemon (not a container). Deploy applies this automatically with:

```bash
sudo bash scripts/configure-tailscale-serve.sh
```

---

## Environment variables

See [.env.example](.env.example) for the authoritative, commented list. Highlights:

- `OPENROUTER_API_KEY` (or `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`) — LLM provider.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (numeric IDs, from @userinfobot), `TELEGRAM_HOME_CHANNEL`.
- `FIRECRAWL_API_URL=http://127.0.0.1:3002`, `HINDSIGHT_API_URL=http://127.0.0.1:8888`.
- `VPS_HOST`, `VPS_DIR` (deploy).
- `HERMES_DATA_DIR` — overrides the bind-mount source for litestream/backup (default `/home/hermes/.hermes`; use `~/.hermes` locally).

---

## Agent state & persistence

Everything lives under `/home/hermes/.hermes` (VPS) / `~/.hermes` (MacBook):

```
.hermes/
├── config.yaml               ← copied from repo on deploy
├── .env                      ← secrets (NOT synced)
├── state.db + wal            ← replicated by Litestream (NOT synced)
├── memories/                 ✓ synced
│   ├── MEMORY.md
│   └── USER.md
├── SOUL.md                   ✓ synced
├── skills/                   ✓ synced
├── wiki/                     ✓ synced (Obsidian vault target)
├── sessions/ logs/ cron/     runtime-only, not synced
└── platforms/                platform auth (WhatsApp/Signal), not synced
```

Each profile has its own subdirectory under `/home/hermes/work/` bind-mounted into the Docker sandbox as `/workspace` — all agent-run commands see only that profile's folder. Nothing outside `work/<profile>/` is reachable from a sandboxed shell. New profiles are added with `make add-profile PROFILE=<name>` or directly on the VPS with `bash /opt/hermes/scripts/provision-profile.sh --profile <name>`.

---

## Backup & Restore

Two complementary mechanisms, both operating on `/home/hermes/.hermes`:

### Litestream (continuous SQLite replication)

`state.db` is a live WAL-mode SQLite DB — it cannot be safely `tar`'d while running. Litestream streams WAL pages to `hermes_backups/litestream/` every 10–30 s and writes full snapshots every 6–12 h.

```bash
make snapshots                                  # list restore points
make restore ARGS="db latest"                   # roll state.db back
make restore ARGS="db 2026-04-05T21:00:00"      # point-in-time restore
```

### docker-volume-backup (daily tarballs)

Every day at 3am on VPS (weekly locally), the entire `.hermes` dir is tarballed to `hermes_backups/`. Retained for 30 days.

```bash
make backup-now
make local-backup-now
make restore ARGS="volume hermes_data_2026-04-05T03-00-00.tar.gz"
make restore ARGS="file memories/MEMORY.md hermes_data_2026-04-05T03-00-00.tar.gz"
```

**Backup locations:**

| Env | Litestream replica | Tarballs |
|---|---|---|
| Local | `./backups/litestream/` | `./backups/*.tar.gz` |
| VPS | `/opt/hermes-backups/litestream/` | `/opt/hermes-backups/*.tar.gz` |

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
| `make snapshots` | List restore points |
| `make restore ARGS="..."` | See Backup & Restore |
| `make clean` | Prune stopped containers + dangling images |
| `make add-profile PROFILE=name` or `make add-profile PROFILE=name TELEGRAM_BOT_TOKEN=***` | Create/update a profile with its own workspace, SOUL override, Hindsight bank, and optional Telegram bot |
| `make sync-souls` | Rerender `SOUL.md` for default + all named profiles from shared sources |

### Local dev

| Target | Description |
|---|---|
| `make local-up` / `local-down` | Support services |
| `make local-status` / `local-logs` | Observability |
| `make local-chat` | `hermes chat` against `~/.hermes` |
| `make local-update-agent` | `hermes update` locally |
| `make local-backup-now` / `local-snapshots` | Backups |

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
Check the tailnet UI at `https://openclaw-vps.taild96651.ts.net/syncthing/`. Verify the MacBook device is approved and the `hermes` folder is shared in both directions.
