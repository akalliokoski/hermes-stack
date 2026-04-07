# Hermes — Setup & Operations

This document covers the deployment layer: local dev, VPS setup, configuration, day-to-day operations, state management, and backup/restore. For agent internals (skills, tools, profiles) see [hermes-agent/README.md](hermes-agent/README.md).

---

## Stack Overview

```
hermes-agent        Main agent process — gateway + all tools
├── litestream      SQLite WAL replication sidecar (state.db backup)
├── backup          Daily volume snapshots (offen/docker-volume-backup)
├── hindsight       Vector memory API + UI  (ports 8888, 9999)
├── firecrawl-api   Web scraping API        (port 3002)
├── firecrawl-worker Web crawl job worker
├── playwright      Headless browser (firecrawl dep)
├── nuq-migrate     One-shot DB schema init (exits after first run)
├── db              PostgreSQL 16 (firecrawl + hindsight queues)
├── redis           Redis 7       (firecrawl rate limiting)
└── rabbitmq        RabbitMQ 3    (firecrawl job queue)

VPS only:
└── syncthing       Sync hermes_data → MacBook over Tailscale
    (Tailscale runs on the VPS host — not in Docker — and serves Hindsight via `tailscale serve`)
```

**Docker Compose files:**

| File | Purpose |
|---|---|
| `docker-compose.yml` | Base — all services + profile base anchor, used everywhere |
| `docker-compose.override.yml` | Local dev overrides (auto-applied) |
| `docker-compose.vps.yml` | VPS additions: Syncthing, Tailscale, host backup path |

---

## Prerequisites

- Docker + Docker Compose v2
- `make`
- VPS: Tailscale installed and authenticated on both VPS and MacBook

---

## Local Dev

### First run

```bash
cp hermes-agent/.env.example .env
# Fill in at minimum: OPENROUTER_API_KEY (or another LLM provider key)
# Fill in: TELEGRAM_BOT_TOKEN if using Telegram

make local-up       # builds image, starts all services
make local-chat     # open interactive chat (in a separate terminal)
```

On first start `nuq-migrate` runs once to initialize the Firecrawl DB schema, then exits. All subsequent starts skip it (already initialized).

### Common commands

```bash
make local-up           # start (builds if needed)
make local-down         # stop and remove containers
make local-restart      # restart only hermes-agent (after config change)
make local-logs         # tail hermes-agent logs
make local-status       # show container status
make local-chat         # interactive hermes chat
make local-backup-now   # trigger immediate backup
make local-snapshots    # list available backups
```

### Config

`config.yaml` at the repo root is bind-mounted read-only into the container at startup. Edit it directly — changes take effect after `make local-restart`.

Key fields:

```yaml
model:
  default: google/gemma-4-26b-a4b-it   # model to use
  provider: openrouter
  base_url: https://openrouter.ai/api/v1

agent:
  max_turns: 60
  reasoning_effort: medium              # low / medium / high

memory:
  provider: ''                          # '' = built-in MEMORY.md; 'hindsight' for vector memory

session_reset:
  mode: both                            # daily + idle reset
  idle_minutes: 1440                    # 24h idle timeout
```

---

## VPS Deployment

### First-time setup

```bash
# 1. On MacBook: copy secrets to VPS
scp .env <vps-host>:/opt/hermes/.env

# 2. On VPS: install Docker, create dirs
ssh <vps-host> 'bash -s' < scripts/vps-setup.sh

# 3. On MacBook: first deploy
make deploy

# 4. On VPS: create backup directory (host bind-mount for hermes_backups)
ssh <vps-host> 'mkdir -p /opt/hermes-backups'

# 5. On VPS: bring stack up
ssh <vps-host> 'cd /opt/hermes && make up'
```

`VPS_HOST` and `VPS_DIR` are read from `.env`:

```bash
VPS_HOST=my-vps           # Tailscale hostname or IP
VPS_DIR=/opt/hermes       # default
```

### Deploying updates

```bash
make deploy
```

This rsyncs the repo (excluding `.env` and `sync/`), pulls updated images, rebuilds `hermes-agent`, and runs `docker compose up -d --remove-orphans`.

### VPS-specific services

**Syncthing** syncs `hermes_data` (memories, sessions, SOUL.md, skills) to MacBook over Tailscale. Access the UI at `http://localhost:8384` via SSH tunnel:

```bash
ssh -L 8384:localhost:8384 <vps-host>
```

After first start, open `http://localhost:8384`, add the MacBook as a remote device, and share the `hermes-data` folder. Enable **Staggered File Versioning** (30 days, 1h interval) for human-readable history of MEMORY.md and SOUL.md.

> Syncthing ignores `state.db*` files — those are handled by Litestream instead.

**Tailscale** exposes the Hindsight memory UI on your tailnet via the host Tailscale daemon (not a Docker container — running Tailscale in Docker conflicts with the host Tailscale TUN device). After first deploy, run once on the VPS:

```bash
tailscale serve --bg --https=443 --set-path /memory/ http://127.0.0.1:8888
tailscale serve --bg --https=443 --set-path /memory-ui/ http://127.0.0.1:9999
```

The serve config persists in Tailscale state and survives reboots. Hindsight will then be available at:
- `https://<vps-hostname>.<tailnet>.ts.net/memory/` — REST API
- `https://<vps-hostname>.<tailnet>.ts.net/memory-ui/` — Control Plane UI

---

## CI/CD (GitHub Actions)

Two workflows live in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `deploy.yml` | Push to `main`, `workflow_dispatch` | Joins tailnet → rsync → `docker compose up` → Telegram notification |
| `validate.yml` | PRs, non-`main` pushes | Validates compose files — no secrets needed |

### One-time setup

**1. Generate a deploy SSH key**

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/hermes_deploy -N ""
# Install the public key on the VPS
ssh <vps-host> "echo '$(cat ~/.ssh/hermes_deploy.pub)' >> ~/.ssh/authorized_keys"
```

**2. Create a Tailscale OAuth client**

In the [Tailscale admin console](https://login.tailscale.com/admin/settings/oauth):
- Create an OAuth client with **Devices: Write** scope
- Note the client ID and secret

In your Tailscale ACL policy, add `tag:ci` to `tagOwners` so the ephemeral CI device can be tagged:

```json
"tagOwners": {
  "tag:ci": ["autogroup:admin"]
}
```

**3. Add GitHub Secrets**

Go to the repo → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `TAILSCALE_OAUTH_CLIENT_ID` | From step 2 |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | From step 2 |
| `VPS_SSH_PRIVATE_KEY` | Contents of `~/.ssh/hermes_deploy` (private key) |
| `VPS_SSH_USER` | SSH user on VPS (e.g. `root`) |
| `VPS_HOST` | Same as `VPS_HOST` in your `.env` |
| `TELEGRAM_BOT_TOKEN` | Same as `TELEGRAM_BOT_TOKEN` in your `.env` |
| `TELEGRAM_HOME_CHANNEL` | Same as `TELEGRAM_HOME_CHANNEL` in your `.env` |

`VPS_DIR` is hardcoded to `/opt/hermes` in the workflow — change it there if needed.

---

## LLM-Wiki & Obsidian

Hermes ships a bundled `llm-wiki` skill (Karpathy's LLM Wiki pattern) that builds
and maintains a persistent, interlinked markdown knowledge base. The wiki lives at
`/opt/data/wiki/` inside the `hermes_data` volume and is synced to your MacBook
via Syncthing — open it as an Obsidian vault with no extra setup.

### Wiki layout

```
/opt/data/wiki/
├── raw/        Immutable source documents (articles, URLs, notes)
├── wiki/       Agent-maintained pages with [[wikilinks]]
├── SCHEMA.md   Domain conventions, tag taxonomy
├── index.md    Page inventory and navigation
└── log.md      Activity log (rotated at 500 entries)
```

### Usage

```
# In Hermes chat:
wiki init                           # set up structure, write SCHEMA.md
wiki ingest https://example.com     # fetch URL, compile into wiki pages
wiki ingest                         # paste raw text (agent prompts for topic)
wiki query "what is X?"             # search wiki and synthesize answer
wiki lint                           # check for broken links, orphan pages
```

### Opening in Obsidian (MacBook)

1. Ensure Syncthing is syncing the `hermes-data` folder (see VPS-specific services above).
2. In Obsidian → **Open folder as vault** → navigate to your Syncthing sync path → select the `wiki/` subfolder.
3. Obsidian renders all `[[wikilinks]]` as clickable links and shows the graph view.

> Tip: Enable **Staggered File Versioning** (30 days, 1h interval) in Syncthing on the `hermes-data` folder to get human-readable history of all wiki edits.

### Config reference

The wiki path is set in `config.yaml` under `skills.config.wiki.path` (default: `/opt/data/wiki`). Change it if you want the wiki stored elsewhere in the volume.

---

## Environment Variables (`.env`)

Required:

```bash
# LLM provider (at least one)
OPENROUTER_API_KEY=sk-or-...

# Messaging platform
TELEGRAM_BOT_TOKEN=...

# VPS deployment
VPS_HOST=my-vps
```

Optional (have defaults):

```bash
# Postgres (default: hermes/hermes/hermes)
POSTGRES_USER=hermes
POSTGRES_PASSWORD=hermes
POSTGRES_DB=hermes

# Firecrawl
BULL_AUTH_KEY=local

# Firecrawl proxy — residential proxies to prevent VPS static IP from being blocked
# Recommended: Decodo (https://decodo.com) or IPRoyal (https://iproyal.com)
# FIRECRAWL_PROXY_SERVER=http://gate.decodo.com:7000
# FIRECRAWL_PROXY_USERNAME=your-username-rotate
# FIRECRAWL_PROXY_PASSWORD=your-password

# Hindsight vector memory
HINDSIGHT_LLM_API_KEY=...
HINDSIGHT_LLM_PROVIDER=openrouter
HINDSIGHT_LLM_MODEL=google/gemma-4-26b-a4b-it
HINDSIGHT_LLM_BASE_URL=https://openrouter.ai/api/v1
HINDSIGHT_DB_PASSWORD=hindsight

# Tailscale (VPS)
TS_AUTHKEY=tskey-auth-...
```

---

## Multiple Profiles

Multiple named profiles can run simultaneously, each with its own gateway process, credentials, memory, and personality. All profiles share the same `hermes_data` volume — isolation is by subdirectory.

### Adding a new profile

```bash
# 1. Create the profile (clones config + SOUL.md from default, fresh memory)
docker compose run --rm hermes-agent hermes profile create <name> --clone

# 2. Set up per-profile credentials
cp profiles/example.env profiles/<name>.env
# Edit profiles/<name>.env — add the bot tokens for this profile (Telegram, Discord, etc.)

# 3. Add a service in docker-compose.yml (uncomment / copy the commented block)
#    Set HERMES_PROFILE: <name> and add profiles/<name>.env to env_file

# 4. Register the profile's state.db with Litestream (continuous backup)
#    Uncomment / copy the commented block in litestream.yml and litestream.local.yml

# 5. Start
docker compose up -d hermes-<name>
```

### Credential files

| File | Purpose |
|---|---|
| `.env` | Shared: LLM API key, Postgres, Firecrawl, VPS config |
| `profiles/<name>.env` | Per-profile: bot tokens (Telegram, Discord, etc.) |
| `profiles/example.env` | Template — committed, no real secrets |

`profiles/*.env` files are git-ignored. The `default` profile reads bot tokens directly from `.env`.

### Per-profile config

By default all profiles share `config.yaml` (same model, memory limits, toolsets). To give a profile its own settings, bind-mount a separate file in `docker-compose.override.yml`:

```yaml
hermes-coder:
  volumes:
    - ./profiles/coder/config.yaml:/opt/data/profiles/coder/config.yaml:ro
```

Personality (`SOUL.md`) is always per-profile and lives inside the `hermes_data` volume.

---

## Agent State & Persistence

All mutable agent state lives in the `hermes_data` Docker volume, mounted at `/opt/data` inside the container.

```
/opt/data/
├── state.db              SQLite: default profile — history, sessions, FTS index
├── state.db-wal          SQLite WAL (managed by Litestream — do not copy raw)
├── memories/
│   ├── MEMORY.md         Default profile memory (2200 char limit)
│   └── USER.md           Default profile user model (1375 char limit)
├── SOUL.md               Default profile persona
├── config.yaml           ← bind-mounted from repo root (read-only)
├── sessions/
│   └── sessions.json     Session key → ID index
├── skills/               User-installed and bundled skills (*.md)
├── platforms/            Platform auth state (WhatsApp, Signal)
├── .env                  API keys (managed separately)
├── logs/                 Rotating log files
├── cron/                 Scheduled task outputs
└── profiles/
    └── <name>/           Named profile — same layout as above
        ├── state.db
        ├── memories/
        ├── SOUL.md
        ├── sessions/
        └── ...
```

`./sync/` is a separate bind-mount for shared files (exported notes, skills) not tied to agent state.

---

## Backup & Restore

The hermes stack runs two complementary backup mechanisms:

### Litestream (continuous SQLite replication)

`state.db` is a live SQLite database in WAL mode — it cannot be safely copied while running. Litestream streams WAL pages to `hermes_backups/litestream/` every 10–30 seconds and writes full snapshots every 6–12 hours. Each named profile has its own `state.db` at `/opt/data/profiles/<name>/state.db` — add a corresponding entry to `litestream.yml` (and `litestream.local.yml`) when creating a new profile.

```bash
make snapshots          # list available restore points (tarballs + Litestream)
```

### docker-volume-backup (daily full snapshots)

Every day at 3am (weekly locally), the entire `hermes_data` volume is checkpointed and archived as a tarball to `hermes_backups/`. Retained for 30 days.

```bash
make backup-now         # trigger immediate backup (VPS)
make local-backup-now   # trigger immediate backup (local)
make snapshots          # list tarballs + Litestream snapshots
```

### Restore

```bash
# List everything available
make restore ARGS="list"

# Roll back state.db to a specific point in time
make restore ARGS="db 2026-04-05T21:00:00"
make restore ARGS="db latest"

# Restore a single file (e.g. after accidental MEMORY.md edit)
make restore ARGS="file memories/MEMORY.md hermes_data_2026-04-05T03-00-00.tar.gz"

# Full disaster recovery from a tarball
make restore ARGS="volume hermes_data_2026-04-05T03-00-00.tar.gz"
```

All modes stop the agent, perform the restore, and restart. See [scripts/restore.sh](scripts/restore.sh) for details.

**Backup locations:**

| Environment | Litestream replica | Tarballs |
|---|---|---|
| Local dev | `./backups/litestream/` | `./backups/*.tar.gz` |
| VPS | `/opt/hermes-backups/litestream/` | `/opt/hermes-backups/*.tar.gz` |

The VPS backup dir is a host bind-mount and survives `docker compose down -v`.

---

## All `make` Targets

### VPS

| Target | Description |
|---|---|
| `make up` | Start full VPS stack |
| `make down` | Stop stack |
| `make restart` | Restart hermes-agent only |
| `make deploy` | Push + redeploy from MacBook |
| `make status` | Show container status |
| `make logs` | Tail hermes-agent logs |
| `make logs-all` | Tail all service logs |
| `make shell` | Bash shell inside hermes-agent |
| `make chat` | Interactive hermes chat |
| `make backup` | Back up non-hermes volumes (postgres, redis, etc.) |
| `make backup-now` | Trigger immediate hermes_data backup |
| `make snapshots` | List all available restore points |
| `make restore ARGS="..."` | Restore (see Backup & Restore above) |
| `make clean` | Remove stopped containers + dangling images |

### Local dev

| Target | Description |
|---|---|
| `make local-up` | Build + start local stack |
| `make local-down` | Stop local stack |
| `make local-restart` | Restart hermes-agent only |
| `make local-build` | Rebuild hermes-agent image |
| `make local-status` | Show container status |
| `make local-logs` | Tail hermes-agent logs |
| `make local-chat` | Interactive hermes chat |
| `make local-backup-now` | Trigger immediate backup |
| `make local-snapshots` | List available restore points |

---

## Troubleshooting

**firecrawl-api keeps restarting**
The NuQ schema wasn't initialized. `nuq-migrate` should handle this automatically on first start. Check: `docker logs hermes-nuq-migrate-1`.

**Telegram warning: "fallback IPs active: 149.154.167.220"**
Normal — this is hermes's own fallback transport arming itself as a safety net. The gateway is connected normally.

**state.db is missing after volume recreation**
Run `make restore ARGS="db latest"` to restore from the Litestream replica before starting the agent.

**Syncthing not syncing**
Check the Syncthing UI at `http://localhost:8384` (via SSH tunnel). Verify the MacBook device is approved and the `hermes-data` folder is shared in both directions.
