# Hermes Stack — AGENTS.md

This repo is the operational home for a self-hosted Hermes homelab stack.

## Mission

Use Hermes as the main operator for:
- sysops
- devops
- devsecops
- monitoring
- backups
- automation

The design goal is simple and elegant, not over-engineered.

Preferred tools:
- Hermes Agent + Hermes skills
- systemd
- Docker Compose
- Tailscale
- Syncthing
- small shell/Python scripts

Rule of thumb: if Hermes plus a repo script can do it, prefer that over inventing another service or control plane.

## Most important workflow rule

If a change requires any of the following:
- sudo
- systemd unit install/update
- gateway refresh/restart
- service restart
- Tailscale Serve reconfiguration
- VPS-side config re-rendering

then the correct path is:
1. review the code changes
2. merge/push to `main`
3. let the GitHub deploy workflow apply the change

Preferred deployment path: push reviewed changes to `main` and let GitHub Actions run the deploy flow.

Do not treat manual VPS commands as the normal way to apply repo changes. Manual commands are for:
- debugging
- recovery
- confirming a fix before committing it to the repo

Repo-first, then deploy.

## Key docs

These are living documents. Keep `AGENTS.md` and `SETUP.md` actively updated whenever architecture, deploy flow, runtime behavior, operational guidance, or verification steps change.

- [SETUP.md](SETUP.md) — deployment, bootstrap, operations, troubleshooting
- [README.md](README.md) — overview
- [Makefile](Makefile) — common entrypoints
- [scripts/provision-profile.sh](scripts/provision-profile.sh) — profile create/update/sync
- [scripts/remote-deploy.sh](scripts/remote-deploy.sh) — VPS deploy/restart flow
- [scripts/verify-environment.sh](scripts/verify-environment.sh) — verification
- [docs/hermes-community-adoption.md](docs/hermes-community-adoption.md) — which third-party/community Hermes extensions this stack adopts

## Current architecture

- Hermes runs natively on the VPS under systemd
- default and always-on named profiles use gateway services such as:
  - `hermes-gateway`
  - `hermes-gateway-<profile>`
- auxiliary services run via Docker Compose
- Tailscale publishes internal web UIs to the tailnet
- Syncthing syncs the shared root (`/home/hermes/sync`)
- shared soul/skills live under `~/.hermes/shared/`

## Community extensions we actively support

Prefer thin, repo-auditable extensions around the native Hermes runtime instead of
adding a second control plane.

Approved additions:
- Hermes WebUI as a tailnet-only chat UI backed by the stock host-native Hermes runtime and shared profile root
- Hermes Workspace V2 as a tailnet-only operator UI backed by Hermes's built-in API server
- Ollama Cloud or a local/OpenAI-compatible Ollama endpoint for delegation/fallback economics
- shared cross-profile skills under `~/.hermes/shared/skills/`, including house orchestration protocols
- experimental plugins only when they are isolated behind a dedicated profile or documented pilot flow

Not adopted by default:
- extra web dashboards/UIs that duplicate Hermes WebUI or Hermes Dashboard without a documented need
- third-party multi-agent harnesses that replace Hermes as the primary orchestrator
- shared-memory plugins that blur profile boundaries without an explicit design and docs update

## Working with `hermes-agent/`

`hermes-agent/` is an upstream submodule.
Do not modify files inside it in this repo unless you intentionally mean to update the submodule pointer.
If a fix is needed for this stack, prefer repo-level changes around the agent.

## Repo conventions

- fix the repo, not just the live host
- prefer boring, proven tools
- keep automation auditable and easy to recover
- keep docs aligned with the real deploy path
- verify changes after editing scripts that affect deploy or runtime behavior

## Practical operator guidance

When changing deploy/runtime behavior, usually inspect these first:
- `SETUP.md`
- `Makefile`
- `deploy.sh`
- `.github/workflows/deploy.yml`
- `scripts/remote-deploy.sh`
- `scripts/provision-profile.sh`
- `scripts/verify-environment.sh`

If the user asks for a live change on the VPS, prefer implementing it in this repo and shipping it through the normal GitHub deploy workflow instead of relying on one-off shell history.
