# Hermes community extensions in hermes-stack

This document records which new Hermes community tooling we actively adopt in this stack and how it fits the repo-first deploy model.

## Goal

Use the most impactful community additions without turning hermes-stack into a pile of overlapping dashboards, sidecars, and memory systems.

The rule is still:
- Hermes runs natively and remains the main operator/runtime
- repo changes are the source of truth
- Tailscale is the only outward-facing publication layer for internal UIs
- shared skills/wikis are preferred over hidden prompt drift

## Adopted now

### 1. Hermes Workspace V2

Status: adopted as the preferred tailnet-only operator UI.

Why:
- zero-fork with upstream `hermes-agent`
- mobile/PWA friendly
- richer than the built-in dashboard for day-to-day operator work
- fits the existing Tailscale-only remote access model

How we run it:
- `docker-compose.vps.yml` runs `ghcr.io/outsourc-e/hermes-workspace:latest`
- bind: `127.0.0.1:3000`
- Tailscale Serve publishes it on `:9446`
- it talks to Hermes's built-in API server on `127.0.0.1:8642`
- API auth comes from `API_SERVER_KEY`

Boundaries:
- Workspace is a UI layer, not a second orchestrator
- Hermes itself still runs natively under systemd

### 2. Ollama strategy for delegation/fallback

Status: adopted as an optional config overlay driven by env vars.

Why:
- reduces dependence on premium models for delegated work
- preserves a cloud path (`ollama-cloud`) and a local-compatible path (`custom` endpoint)
- keeps the primary interactive model unchanged

How we run it:
- `scripts/apply-model-strategy.py` post-processes rendered profile `config.yaml`
- it is called by `scripts/provision-profile.sh`
- if `OLLAMA_API_KEY` is set, delegation/fallback use provider `ollama-cloud`
- if `HERMES_OLLAMA_BASE_URL` is set, delegation/fallback use a named custom provider against that endpoint

Boundaries:
- we intentionally do not auto-switch the primary model
- `smart_model_routing` stays opt-in

### 3. House orchestration skill

Status: adopted via shared skill.

Why:
- the strongest community pattern is a way of operating subagents, not just another plugin
- we want explicit retry -> replan -> decompose behavior
- we want stateless workers and structured handoffs, not ad hoc prompt spaghetti

How we run it:
- shared skill under `~/.hermes/shared/skills/autonomous-ai-agents/hermes-stateless-worker-orchestration`
- available to every profile through `skills.external_dirs`
- documented here and in `SETUP.md`

## Experimental only

### Icarus plugin

Status: not enabled by default.

Reason:
- promising for markdown-fabric capture and training-data extraction
- but it introduces another memory-like layer next to Hindsight
- profile-isolated Hindsight remains the default memory architecture

If piloted later:
- use a dedicated profile
- store notes under the synced wiki tree
- treat it as note capture first, not auto-model replacement

### Maestro

Status: not adopted.

Reason:
- might help if long-running missions outgrow sessions + cron + wiki + Workspace
- not justified yet as another harness layer

## Not adopted by default

- alternate web UIs that overlap with Workspace V2
- third-party orchestration layers that replace Hermes as the primary coordinator
- shared-memory plugins that bypass profile boundaries without a deliberate architecture update

## Operational consequences

If a change touches any of the following, it belongs in the repo and should ship through the normal deploy path:
- Workspace service wiring
- API server env/config
- Tailscale Serve routes
- profile rendering/model-strategy rewrites
- shared skills that define house orchestration patterns

## Validation checklist

When these features change, verify at minimum:
- `docker compose -f docker-compose.yml -f docker-compose.vps.yml config`
- `bash scripts/verify-local-web-bindings.sh`
- `bash scripts/verify-tailnet-web-routes.sh`
- `bash scripts/verify-environment.sh --all-profiles --service-mode auto`
- `curl http://127.0.0.1:8642/health` when the API server is enabled
