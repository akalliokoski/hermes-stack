# Hermes — Setup & Operations

This document covers the deployment layer: local dev, VPS setup, configuration, day-to-day ops, state, and backup/restore.

This is a living document. Keep it actively updated when deploy flow, runtime architecture, profile behavior, verification steps, or recovery procedures change.

**Topology.** `hermes-agent` runs natively on the VPS under systemd (user: `hermes`), installed via the upstream [install.sh](https://hermes-agent.nousresearch.com/docs/getting-started/installation). On the VPS, the default and always-on gateway profiles use Hermes's local terminal backend so CLI and mobile/gateway sessions share the same profile behavior and workspaces. Docker Compose runs the auxiliary services: firecrawl, hindsight, litestream, backup, and on the VPS the tailnet-facing support apps such as Syncthing, Audiobookshelf, and Jellyfin. Hermes's built-in dashboard/API remain the canonical web control surfaces; third-party UIs like Hermes Workspace should be treated as optional experiments until their packaging is stable.

---

## Stack Overview

```
VPS host
├── systemd: hermes-gateway.service          (user: hermes)
│     └── hermes gateway run                 (state in /home/hermes/.hermes)
│           └── local terminal backend in /home/hermes/work/<profile>
│
└── docker compose
      ├── firecrawl-api  + firecrawl-worker  127.0.0.1:3002 (web scraping)
      ├── playwright, redis, db, rabbitmq, nuq-migrate
      ├── hindsight                          127.0.0.1:8888 / 9999 (vector memory)
      ├── litestream                         continuous state.db WAL replication
      ├── backup                             daily /home/hermes/.hermes tarball
      ├── syncthing (VPS only)               sync /home/hermes/sync → MacBook
      │                                      over Tailscale
      ├── audiobookshelf (VPS only)          127.0.0.1:13378 podcast delivery
      └── jellyfin (VPS only)                127.0.0.1:8096 video delivery
```

**Compose files:**

| File | Purpose |
|---|---|
| `docker-compose.yml` | Base — auxiliary services only |
| `docker-compose.override.yml` | Local dev overrides (auto-applied) |
| `docker-compose.vps.yml` | VPS additions: syncthing, Audiobookshelf, Jellyfin, and host data bind-mounts |

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

### Ollama delegation/fallback strategy

hermes-stack keeps the main interactive loop on the configured primary model (currently Codex/GPT-5.4 by default), but can post-process rendered profile configs to push delegated work and provider fallback onto Ollama.

Two supported modes:

1. Ollama Cloud
   - set `OLLAMA_API_KEY`
   - optional overrides: `HERMES_OLLAMA_DELEGATION_MODEL`, `HERMES_OLLAMA_FALLBACK_MODEL`
   - profile configs are rewritten to use provider `ollama-cloud` for `delegation` and `fallback_model`

2. Local/custom Ollama-compatible endpoint
   - set `HERMES_OLLAMA_BASE_URL` (for example `http://127.0.0.1:11434/v1`)
   - set `HERMES_OLLAMA_MODEL` or both `HERMES_OLLAMA_DELEGATION_MODEL` and `HERMES_OLLAMA_FALLBACK_MODEL`
   - optional overrides: `HERMES_OLLAMA_PROVIDER_NAME`, `HERMES_OLLAMA_ENDPOINT_API_KEY`
   - profile configs are rewritten to add a named `custom_providers` entry and point delegation/fallback at that endpoint

The rewriting happens in `scripts/apply-model-strategy.py`, which is called by `scripts/provision-profile.sh` after `render-config.py`. That means repo-driven profile syncs remain the source of truth; you do not need to click through `hermes model` on every profile after deploy.

The strategy is explicit on purpose: it changes `delegation` and `fallback_model`, not the primary `model.provider`, so the top-level operator loop stays predictable.

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

After bootstrap, the first `git push` to `main` (or a manual `make deploy`) rsyncs the repo, renders the latest VPS config, syncs all profiles/environment context, brings up the support stack, and starts `hermes-gateway` if it is not already running. Later deploys only restart gateway services when their rendered config or systemd unit changed, so routine stack deploys do not interrupt active chats unnecessarily. Gateway services now also self-heal stale `gateway.pid` and scoped lock files before each start via a repo-owned `ExecStartPre` cleanup helper, so the host can keep using stock Hermes Agent while recovering automatically from stale gateway state.

`VPS_HOST` and `VPS_DIR` are read from `.env`:

```bash
VPS_HOST=my-vps           # Tailscale hostname or IP
VPS_DIR=/opt/hermes       # default
```

The individual scripts can also be run standalone (e.g. `ssh $VPS_HOST 'sudo bash -s' < scripts/vps-setup.sh`) if you want to skip the wipe on a fresh VPS.

### Deploying updates

```bash
make deploy          # rsync repo, refresh systemd units/profile config, restart only gateways that changed or are inactive
make update-agent    # bumps hermes to latest (runs `hermes update` on VPS)
```

Gateway services should be operated through the systemd units managed by this repo, not by long-running ad hoc foreground shells. The unit entrypoint remains the stock Hermes command `hermes gateway run --replace`; hermes-stack adds a host-side `ExecStartPre=/usr/bin/python3 /opt/hermes/scripts/cleanup-hermes-gateway-state.py` so each start clears only stale gateway PID/lock records first.

That means the steady-state pattern is:

1. render/update config and units from `hermes-stack`
2. start or restart `hermes-gateway` / `hermes-gateway-<profile>` with systemd
3. let `ExecStartPre` clean stale `gateway.pid`, takeover markers, and dead scoped lock files
4. let stock Hermes start normally with `hermes gateway run --replace`

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
sudo bash scripts/provision-profile.sh --sync-all-profiles --gateway skip      # config-only normalization
sudo bash scripts/provision-profile.sh --sync-all-profiles --gateway existing  # refresh existing named-profile gateways too

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
- renders named-profile hardening drop-ins that also run the same `cleanup-hermes-gateway-state.py` preflight before startup
- when `--sync-all-profiles --gateway existing` is used, refreshes hardening drop-ins and restarts only named-profile gateways that already exist as systemd units

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

Use `--gateway skip` for pure config normalization. Use `--gateway existing` when you also want deploy-time refresh of already-installed named-profile gateway units and their drop-in overrides without creating brand new gateways.

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

`make deploy` / `scripts/remote-deploy.sh` go one step further than the manual config-only command above: deploy uses `--sync-all-profiles --gateway existing`, refreshes existing named-profile gateway drop-ins, restarts `hermes-gateway`, restarts any existing `hermes-gateway-<profile>` units (such as `hermes-gateway-gemma`), and then re-applies Tailscale Serve plus web-binding verification.

`scripts/remote-deploy.sh` now also writes a timestamped log under `/opt/hermes-backups/deploy-logs/` by default and includes the failing `step=...`, `command=...`, `exit=...`, and `log=...` path in its error trap output. The GitHub deploy workflow pins a per-run log path (for example `/opt/hermes-backups/deploy-logs/github-run-<run-id>.log`) and, on failure, appends the tail of that remote log to the Actions step summary so the last failing command is visible without manually SSHing into the VPS.

### VPS-specific services

**Syncthing** now synchronizes the machine-agnostic shared root at `/home/hermes/sync`, not the entire live `~/.hermes` runtime directory. The important split is:

- synced: `wiki/`, shared `soul/`, shared `skills/`, `exports/`, backup archives, copied env manifests
- not blindly synced: `~/.hermes/.env`, live `state.db*`, sessions/logs/cron caches, platform auth, host-specific runtime config

Open the Hermes stack landing page from any tailnet device:

```text
https://<current-tailscale-node-name>.<your-tailnet>.ts.net/
```

That landing page links to the Hermes dashboard, Syncthing UI, Hindsight UI/API, Firecrawl API, Audiobookshelf, and Jellyfin. Direct paths are also available:

- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9444/` (Hermes Dashboard)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9445/` (Syncthing UI)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:13378/` (Audiobookshelf UI/API)
- `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:8096/` (Jellyfin UI/API)
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

#### Built-in Hermes API server

The built-in Hermes API server remains available for local integrations and future UI experiments, but Hermes Workspace V2 is not currently deployed as always-on infrastructure in this stack.

Current shape:
- Hermes itself still runs natively through `hermes-gateway.service`
- the gateway's built-in API server stays bound to `127.0.0.1:8642`
- no third-party Workspace container is deployed by default

Required env in `/home/hermes/.hermes/.env` before deploy:

```bash
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8642
API_SERVER_KEY=<long-random-secret>
```

Recommended hardening:
- generate `API_SERVER_KEY` with `openssl rand -hex 32`
- keep the API server bound to localhost only
- publish outward-facing interfaces only through Tailscale Serve
- if you later add a browser client that needs CORS, set `API_SERVER_CORS_ORIGINS` to that exact origin

The deploy flow now validates `http://127.0.0.1:8642/health` whenever the API server is enabled. Workspace V2 should only be reintroduced after upstream packaging proves stable enough for unattended deploys.

### Podcast and video pipeline helpers

Deploy also installs a dedicated podcast pipeline venv for Hermes under:

```text
/home/hermes/.venvs/podcast-pipeline/bin/python
```

That venv contains validated dependencies for:
- `modal`
- `podcastfy==0.4.3`
- `playwright` (Python package)
- `mutagen`

The podcast pipeline now follows a thin-skill / repo-tools split:

- skill responsibility: prompt conventions, transcript style, operator guidance
- repo responsibility: reusable runtime tools under `/opt/hermes/scripts/`

Canonical repo tools:

```text
/opt/hermes/scripts/make-podcast.py
/opt/hermes/scripts/podcast_transcript_schema.py
/opt/hermes/scripts/podcast_transcript_prompting.py
/opt/hermes/scripts/podcast_transcript_audit.py
/opt/hermes/scripts/render_podcast_transcript.py
/opt/hermes/scripts/make-manim-video.py
/opt/hermes/scripts/run_podcastfy_pipeline.py
/opt/hermes/scripts/audiobookshelf_api.py
/opt/hermes/scripts/bootstrap-audiobookshelf.py
/opt/hermes/scripts/modal_chatterbox_openai.py
/opt/hermes/scripts/sync-modal-hf-secret.py
```

The repo also includes a deployable Modal app for Chatterbox at:

```text
/opt/hermes/scripts/modal_chatterbox_openai.py
```

Before deploying the Modal app, sync Hugging Face auth from the main Hermes env into Modal's remote secret store:

```bash
python3 /opt/hermes/scripts/sync-modal-hf-secret.py
```

That keeps `HF_TOKEN` in the main Hermes `.env` as the local source of truth while still copying it into Modal's required remote secret.

For distinct two-host production voices, the Modal volume must contain real prompt WAVs for both host aliases. The canonical shape is:

```text
/voices/chatterbox-tts-voices/prompts/female.wav
/voices/chatterbox-tts-voices/prompts/male.wav
```

The deployed helper resolves aliases deterministically as:
- `female` / `shimmer` / `nova` -> `female.wav`
- `male` / `echo` / `alloy` -> `male.wav`

If one of those canonical alias groups is requested but the corresponding prompt file is missing, the API now returns an explicit error instead of silently collapsing both speakers onto `Lucy.wav`.

Deploy the Modal app from the VPS after authenticating with Modal (`modal setup`), for example:

```bash
/home/hermes/.venvs/podcast-pipeline/bin/python -m modal deploy /opt/hermes/scripts/modal_chatterbox_openai.py
```

Use the resulting HTTPS URL as `TTS_BASE_URL`.
For the repo's `scripts/modal_chatterbox_openai.py` helper, keep it as the bare Modal app URL (no `/v1` suffix); the helper serves both `/audio/speech` and `/v1/audio/speech` compatibility routes and returns real MP3 bytes for default/mp3 requests.

Operational note: the helper now keeps prompt-inspection details behind `HERMES_CHATTERBOX_DEBUG`. In normal production mode, `/health` still reports alias resolution and available prompt files, but deep prompt metadata and the `/debug/prompt/{voice}` route are only exposed when `HERMES_CHATTERBOX_DEBUG=1` is set for the Modal deployment.

The main orchestration entrypoint is:

```bash
python3 /opt/hermes/scripts/make-podcast.py --title "AI Research Weekly" --source-file /path/to/notes.md --tts-base-url https://<workspace>--hermes-chatterbox-openai.modal.run --dry-run
```

The transcript path is now structured-first:
- `make-podcast.py` builds a source packet from files/URLs/topic/notes
- Hermes is called twice when generating from sources:
  - draft pass -> canonical `transcript-draft.json`
  - revision pass -> canonical `transcript.json`
- local helpers validate the JSON schema and run a transcript audit, writing `transcript-audit.json`
- the audit now also warns on transcript plainness patterns such as muted emotion contrast or weak post-peak release, so flat-but-valid scripts are easier to catch before TTS
- the canonical JSON is rendered to Podcastfy-compatible `<Person1>/<Person2>` dialogue as `transcript.txt`
- `run_podcastfy_pipeline.py` accepts canonical transcript JSON only; legacy raw `HOST_A:` / `HOST_B:` transcript text now hard-fails
- for generated episodes, the shared wiki now archives:
  - `*-transcript-structured.json`
  - `*-transcript-audit.json`
  - `*-transcript-rendered.md`

Dry-run behavior:
- `--dry-run` still produces transcript artifacts and audit output
- `--dry-run` skips TTS/audio synthesis and therefore does not require a TTS base URL

Required env/config for a real run:
- `TTS_BASE_URL` or `CHATTERBOX_BASE_URL`
- `AUDIOBOOKSHELF_BASE_URL` optional (defaults to `http://127.0.0.1:13378`)
- recommended for non-interactive scans/verifications: `AUDIOBOOKSHELF_TOKEN`
- bootstrap/login fallback: `AUDIOBOOKSHELF_ADMIN_USERNAME`, `AUDIOBOOKSHELF_ADMIN_PASSWORD`
- optional Audiobookshelf overrides: `AUDIOBOOKSHELF_LIBRARY_NAME`, `AUDIOBOOKSHELF_PODCASTS_PATH`
- `PODCASTFY_PYTHON` optional if the podcast venv lives somewhere non-default at runtime
- `TTS_BASE_URL=https://<workspace>--hermes-chatterbox-openai.modal.run` or `CHATTERBOX_BASE_URL=...`, `PODCASTFY_PYTHON=/home/hermes/.venvs/podcast-pipeline/bin/python`, `PODCAST_LIBRARY_ROOT=/data/audiobookshelf/podcasts/profiles`, `PODCAST_PROJECTS_DIR=/data/audiobookshelf/projects`.
- `VIDEO_LIBRARY_ROOT=/data/jellyfin/videos/profiles`, `VIDEO_PROJECTS_DIR=/data/jellyfin/projects`, `VIDEO_SERIES=notebooklm-style-explainers`, `VIDEO_PIPELINE_VENV=/home/hermes/.venvs/video-pipeline` for the Jellyfin explainer workflow. The pipeline now keeps project artifacts out of the served library tree and publishes only clean final MP4/SRT outputs into profile-specific Jellyfin library roots.
- `scripts/remote-deploy.sh` now installs the required Ubuntu packages for local Manim rendering (`build-essential`, `python3-dev`, `pkg-config`, `libcairo2-dev`, `libpango1.0-dev`, `ffmpeg`) and bootstraps the dedicated venv via `/opt/hermes/scripts/setup-video-pipeline.sh`.
- `WIKI_PATH=/home/hermes/sync/wiki` if you want transcript/brief archives written somewhere other than the shared synced wiki default.
- `HF_TOKEN` if your Modal Chatterbox deploy needs Hugging Face auth (sync it into Modal with `python3 /opt/hermes/scripts/sync-modal-hf-secret.py`)
- `PODCASTFY_VENV` optional when bootstrapping the podcast helper venv somewhere else
- optional `TELEGRAM_BOT_TOKEN` + `TELEGRAM_HOME_CHANNEL` for ready notifications
- `PODCAST_VOICE_PERSON1=shimmer` and `PODCAST_VOICE_PERSON2=echo` keep Person1/HOST_A on the female alias and Person2/HOST_B on the male alias end-to-end
- optional legacy/local fallback transport only: `KOKORO_BASE_URL`
- during `scripts/remote-deploy.sh`, repo/runtime env values from `/opt/hermes/.env` (and matching GitHub Actions env/secrets when provided) are loaded before `provision-profile.sh`, then synced into each profile env file such as `/home/hermes/.hermes/.env`. This keeps chat-triggered helpers like `make-podcast.py` able to reuse Audiobookshelf/TTS/Telegram settings non-interactively after deploy.

The repo tools can:
- ask Hermes to generate a structured transcript from local files, URLs, inline text, or a topic hint
- run a two-pass transcript flow (draft JSON -> revision JSON -> local audit)
- render canonical transcript JSON into Podcastfy-compatible tags
- require canonical transcript JSON for all transcript inputs
- publish order-first filenames directly from `episode_slug` without auto-prepending a date
- write clean published podcast MP3s into `/data/audiobookshelf/podcasts/profiles/<profile>/<show-slug>/<episode-slug>.mp3`
- keep transcript/audit/source artifacts under `/data/audiobookshelf/projects/<profile>/<show-slug>/<episode-slug>/`
- archive generated podcast transcript artifacts into the shared wiki under `raw/transcripts/media/podcasts/`, including structured transcript JSON, audit JSON, and rendered transcript markdown
- trigger an Audiobookshelf scan for the active profile library
- send a Telegram notification when configured
- scaffold explainer projects under `/data/jellyfin/projects/<profile>/<series>/<date_slug>/`
- archive each explainer brief into the shared wiki under `raw/transcripts/media/video-explainers/`
- in narrated mode, also write `scene_manifest.json` and `narration-script.md` so narration timing becomes the authoritative spec
- archive narrated explainer scripts into the shared wiki for later reuse/debugging
- save `brief.md`, `source-packet.md`, `slides.md`, and `render.sh` so Jellyfin-backed video work can start from a repeatable project layout
- keep explainer videos silent by default unless you explicitly opt into narration
- for narrated explainers, synthesize one clip per scene, measure durations, normalize audio, and let the infographic renderer conform to the manifest-driven timing instead of trimming one monolithic voice track over a finished video

Jellyfin serves the resulting MP4s from `/data/jellyfin/videos` on the host, mounted as `/media/videos` inside the container. `scripts/bootstrap-jellyfin.py` now creates one home-video library per Hermes profile, enables realtime monitoring for each profile library, and points them at `/media/videos/profiles/<profile>`. The legacy `AI Generated Videos` library is kept on `/media/videos/ai-generated` so profile libraries do not duplicate those items. The video pipeline keeps briefs/manifests/renders under `/data/jellyfin/projects/<profile>/...` and publishes only clean final MP4/SRT outputs into the served library tree.

---

## Environment variables

See [.env.example](.env.example) for the authoritative, commented list. Highlights:

- `OPENROUTER_API_KEY` (or `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`) — LLM provider.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (numeric IDs, from @userinfobot), `TELEGRAM_HOME_CHANNEL`.
- optional local service URL overrides: `FIRECRAWL_API_URL=http://127.0.0.1:3002`, `HINDSIGHT_API_URL=http://127.0.0.1:8888`, `AUDIOBOOKSHELF_BASE_URL=http://127.0.0.1:13378`, `JELLYFIN_BASE_URL=http://127.0.0.1:8096`.
- `AUDIOBOOKSHELF_TOKEN` for non-interactive scans/verification, or `AUDIOBOOKSHELF_ADMIN_USERNAME` + `AUDIOBOOKSHELF_ADMIN_PASSWORD` as a login/bootstrap fallback.
- on the VPS itself, `scripts/audiobookshelf_api.py` can also fall back to the local Audiobookshelf SQLite user token cache when explicit auth env vars are absent; explicit env vars are still preferred for portability.
- optional Audiobookshelf library overrides: `AUDIOBOOKSHELF_LIBRARY_NAME`, `AUDIOBOOKSHELF_PODCASTS_PATH`.
- `TTS_BASE_URL=https://<workspace>--hermes-chatterbox-openai.modal.run` or `CHATTERBOX_BASE_URL=...`, `PODCASTFY_PYTHON=/home/hermes/.venvs/podcast-pipeline/bin/python`, `PODCAST_LIBRARY_ROOT=/data/audiobookshelf/podcasts/profiles`, `PODCAST_PROJECTS_DIR=/data/audiobookshelf/projects`.
- `VIDEO_LIBRARY_ROOT=/data/jellyfin/videos/profiles`, `VIDEO_PROJECTS_DIR=/data/jellyfin/projects`, `VIDEO_SERIES=notebooklm-style-explainers`, `VIDEO_PIPELINE_VENV=/home/hermes/.venvs/video-pipeline`.
- optional narrated-explainer overrides: `VIDEO_NARRATION_VOICE=Lucy`, `TTS_BASE_URL=https://<workspace>--hermes-chatterbox-openai.modal.run` or `CHATTERBOX_BASE_URL=...`.
- narrated explainer scaffolds now create `scene_manifest.json` + `narration-script.md`; `render.sh` can synthesize per-scene clips, assemble a normalized master narration track, render infographic scene clips, and emit `captions/final.srt` when a TTS base URL is configured.
- To bootstrap or repair the infographic video runtime manually, run `bash /opt/hermes/scripts/setup-video-pipeline.sh` on the VPS; it provisions the dedicated video venv and verifies the ffmpeg-backed renderer path. The script expects `uv` on your `PATH` (for Hermes that is typically `~/.local/bin/uv`).
- `WIKI_PATH=/home/hermes/sync/wiki` to override where podcast transcripts and explainer briefs are archived.
- `HF_TOKEN` as the local source of truth for Modal's `hf-token` secret; sync it with `python3 /opt/hermes/scripts/sync-modal-hf-secret.py` before deploys that need Hugging Face auth.
- optional setup override: `PODCASTFY_VENV=/home/hermes/.venvs/podcast-pipeline` when bootstrapping the podcast venv somewhere else.
- optional legacy/local fallback: `KOKORO_BASE_URL=http://<mac-tailnet-name>.ts.net:8880/v1`.
- `VPS_HOST`, `VPS_DIR` (deploy).
- `HERMES_DATA_DIR` — overrides the bind-mount source for litestream/backup (default `/home/hermes/.hermes`; use `~/.hermes` locally).
- optional deploy diagnostics overrides for `scripts/remote-deploy.sh`: `REMOTE_DEPLOY_LOG_DIR`, `REMOTE_DEPLOY_LOG`.

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

`.github/workflows/deploy.yml` still runs on push to `main`: joins tailnet → rsync → `docker compose up -d` → `scripts/remote-deploy.sh`. The deploy script now restarts `hermes-gateway` (and named profile gateways) only when their rendered config or installed systemd unit changed; otherwise it leaves running gateways alone. Secrets unchanged (`VPS_HOST`, `VPS_SSH_*`, `TAILSCALE_OAUTH_*`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_HOME_CHANNEL`). The old "build hermes-agent image" step is gone.

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

**Gateway/profile command behavior differs from CLI expectations**
Check the rendered profile config (`~/.hermes/config.yaml` or `~/.hermes/profiles/<name>/config.yaml`). On the VPS, always-on gateway profiles should use `terminal.backend: local` and `terminal.cwd: /home/hermes/work/<profile>`. If a profile still shows `backend: docker`, rerender with `python3 scripts/render-config.py ... --output ...` or `sudo bash scripts/provision-profile.sh --sync-all-profiles --gateway skip`, then restart the relevant gateway unit.

**firecrawl-api keeps restarting**
`nuq-migrate` didn't complete. Check `docker compose logs nuq-migrate`.

**state.db missing after a wipe**
`make restore ARGS="db latest"` before restarting the gateway.

**Telegram warning: "fallback IPs active: 149.154.167.220"**
Normal — hermes's own fallback transport arming itself. Gateway is connected.

**Syncthing not syncing**
Check the tailnet UI at `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:9445/`. Verify the MacBook device is approved and the `hermes` folder is shared in both directions.
