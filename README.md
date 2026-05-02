# Hermes Stack

Hermes Stack is a repo-first, self-hosted operating environment for Hermes Agent.

The core idea is simple:
- run Hermes Agent natively on the VPS
- keep deploy logic, profile rendering, and operational docs in this repo
- use Docker Compose only for support services
- publish internal web UIs through Tailscale instead of opening public ports
- let Hermes itself be the day-to-day operator

This repository is the operational home for that setup.

## What this stack includes

### 1. Hermes Agent runtime

Hermes Agent is the primary operator: a terminal and gateway AI agent with tools, persistent memory, skills, cron jobs, delegation, and profile isolation.

In this setup, Hermes itself stays close to upstream:
- installed natively on the host via the upstream install script
- managed by systemd instead of running inside Docker
- configured from rendered profile-local `config.yaml` files
- extended mainly through repo scripts, shared SOUL files, and shared skills

That means the stack prefers repo-level wrappers and configuration over patching Hermes core.

### 2. Profile-aware operator environment

Profiles are used to isolate behavior while sharing common instructions.

Current model:
- default profile home: `~/.hermes`
- named profile homes: `~/.hermes/profiles/<name>/`
- shared SOUL sources: `~/.hermes/shared/soul/base.md` and `~/.hermes/shared/soul/profiles/<name>.md`
- shared skills root: `~/.hermes/shared/skills/`
- profile workspaces: `/home/hermes/work/<profile>`
- profile-isolated Hindsight banks: `hermes-<profile>`

This gives shared operating doctrine without merging long-term memory across profiles.

### 3. Support services

Docker Compose runs the surrounding services Hermes uses:

| Service | Role | Typical endpoint |
|---|---|---|
| Hermes WebUI | Upstream chat-first Hermes browser UI with profile switching | `127.0.0.1:8787` via Tailscale `:9446` |
| Hermes Dashboard | Built-in Hermes web UI | `127.0.0.1:9119` via Tailscale `:9444` |
| Firecrawl | Web crawling / scraping backend | `127.0.0.1:3002` |
| Hindsight | Long-term semantic memory service | `127.0.0.1:8888` API, `127.0.0.1:9999` UI |
| Litestream | Continuous SQLite WAL replication for Hermes state | internal |
| Backup | Daily `.hermes` snapshots + Hindsight SQL dump hook | internal |
| Syncthing | Syncs `/home/hermes/sync` to other machines | `127.0.0.1:8384` via Tailscale `:9445` |
| Tailscale Serve | Tailnet-only publication layer | `https://vps.taild96651.ts.net/` |

## Live VPS shape

At the time this overview was generated, the VPS had these host-native Hermes services active:
- `hermes-gateway.service`
- `hermes-gateway-gemma.service`
- `hermes-webui.service`
- `hermes-dashboard.service`

And these published Tailnet entrypoints:
- `https://vps.taild96651.ts.net/` → landing page + `/memory/` + `/firecrawl/`
- `https://vps.taild96651.ts.net:9443/` → Hindsight UI
- `https://vps.taild96651.ts.net:9446/` → Hermes WebUI
- `https://vps.taild96651.ts.net:9444/` → Hermes Dashboard
- `https://vps.taild96651.ts.net:9445/` → Syncthing UI

## Architecture in one view

```text
Clients
  ├─ Hermes CLI on VPS
  ├─ Mobile / messaging platforms
  └─ Tailnet browser access
           │
           ▼
Host-native Hermes Agent
  ├─ systemd: hermes-gateway
  ├─ systemd: hermes-gateway-<profile>
  ├─ systemd: hermes-webui
  ├─ systemd: hermes-dashboard
  ├─ profile config + SOUL rendering
  ├─ shared skills / shared wiki access
  └─ workspaces under /home/hermes/work/<profile>
           │
           ├─ uses Firecrawl for web extraction/crawling
           ├─ uses Hindsight for long-term memory
           ├─ persists local state under /home/hermes/.hermes
           └─ coordinates content pipelines and operator workflows

Docker Compose support stack
  ├─ Firecrawl + worker + playwright + redis + postgres + rabbitmq
  ├─ Hindsight
  ├─ Litestream
  ├─ Backup
  └─ Syncthing
           │
           ▼
Tailscale Serve
  └─ publishes selected localhost UIs to the tailnet only
```

## Why the split matters

This stack intentionally separates concerns:

### Hermes stays native
Benefits:
- easier upstream updates with `hermes update`
- cleaner systemd integration
- no need to rebuild an agent container for normal upgrades
- CLI, gateway, dashboard, skills, memory, and profiles behave like stock Hermes

### Support services stay in Compose
Benefits:
- easier service restarts and inspection
- clear data mounts and backup paths
- straightforward layering for VPS-only services
- simpler Tailscale publication model

### Repo stays the source of truth
Benefits:
- deploys are auditable
- architecture changes are documented near the code
- profile provisioning and environment rendering are reproducible
- Hermes can operate the system through the same repo it documents

## Key workflows

### Deploy and operations
Common commands live in `Makefile`.

Examples:

```bash
make deploy
make status
make logs
make update-agent
make add-profile PROFILE=<name>
make sync-souls
make sync-profiles
make verify-env
```

Preferred deploy pattern:
1. change the repo
2. commit and push to `main`
3. let the GitHub deploy workflow apply the change

### Profile provisioning
Canonical path:

```bash
sudo provision-profile <name>
# or
sudo bash /opt/hermes/scripts/provision-profile.sh --profile <name>
```

What provisioning does:
- creates or normalizes the profile home
- renders profile `config.yaml`
- renders profile `ENVIRONMENT.md`
- renders profile `SOUL.md` from shared base + profile override
- assigns the profile a dedicated workspace
- writes Hindsight config using bank `hermes-<profile>`
- optionally manages the profile gateway service

### Memory and durability
The stack uses multiple layers of persistence:
- Hermes local state in `/home/hermes/.hermes`
- Litestream WAL replication for SQLite state
- daily `.hermes` archive backups
- logical Hindsight SQL dumps
- Syncthing replication of `/home/hermes/sync`
- shared wiki under `/home/hermes/sync/wiki`

This follows a defense-in-depth durability model rather than relying on one backup path.

## Related docs

- `AGENTS.md` — repo operating rules and architecture guardrails
- `SETUP.md` — detailed deployment, bootstrap, recovery, and troubleshooting guide
- `docs/hermes-community-adoption.md` — supported community extensions and boundaries
- `web/landing/index.html` — tailnet landing page for web UIs
- `web/landing/stack-demo.html` — visual infographic / demo page for this stack

## Demo / summary use cases

This stack is designed to support workflows like:
- chat-driven VPS operations from Hermes itself
- mobile gateway control over Telegram or other adapters
- shared multi-profile knowledge with isolated long-term memory
- automated web research with Firecrawl
- durable recall and semantic memory with Hindsight
- podcast generation tooling and transcript archiving
- explainer-video generation tooling and brief archiving
- shared cross-device notes and artifacts through Syncthing

## Design principles

- Hermes is the operator, not just a chatbot
- repo-first beats one-off shell history
- upstream Hermes stays mostly stock
- profiles share doctrine, not memory banks
- internal services stay localhost-bound when possible
- Tailscale is the publication boundary
- boring infrastructure wins over clever infrastructure

## Fast orientation

If you are new to this repo, start here:
1. read `AGENTS.md`
2. read `SETUP.md`
3. open `web/landing/stack-demo.html`
4. inspect `docker-compose.yml` and `docker-compose.vps.yml`
5. inspect `scripts/provision-profile.sh`
6. inspect `config/base.yaml` and `config/env/vps.yaml`

That gives the shortest accurate tour of how Hermes Agent, hermes-stack, and the related services fit together.
