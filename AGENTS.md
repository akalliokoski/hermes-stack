# Hermes Agent — AGENTS.md

This document describes the agent architecture, components, and conventions for the Hermes project.

## Philosophy

**Simple, not clever. Beautiful, not baroque.**

Prefer tools that do one thing well and compose cleanly. When something already exists and is trusted by the community, use it — don't reinvent it. The goal is a system you can understand at 2am when something breaks.

- **Tailscale** instead of VPN config hell — zero-config mesh networking that just works
- **Syncthing** instead of custom sync scripts — open, reliable, no cloud middleman
- **Litestream** instead of database servers — SQLite is enough; replicate it simply
- **Docker Compose** instead of Kubernetes — it's a personal agent, not a datacenter
- **SQLite + FTS5** instead of Postgres for sessions — fast, embedded, zero maintenance
- **Markdown files** for memory and skills — human-readable, diffable, no schema migrations

When adding something new: reach for the boring, proven tool first. Complexity is a liability. If the solution needs a diagram to explain, simplify it. If a $5/month VPS can run it, that's a feature.

> Resist the urge to add abstraction layers, configuration options, or "future-proofing" that nothing currently needs.

## Overview

Hermes is a self-improving AI agent framework that runs persistently on VPS infrastructure. It supports autonomous task execution via a rich tool ecosystem (40+ tools), multi-platform messaging integration, persistent memory, and autonomous skill creation.

The agent runs as a Docker service on a VPS (~$5/month idle cost via serverless backends like Modal/Daytona) and is accessible via CLI or messaging platforms (Telegram, Discord, Slack, WhatsApp, Signal, Matrix, Email, and more).

---

## Agent Types

### 1. Primary Agent (Hermes)

The main `AIAgent` class in [hermes-agent/run_agent.py](hermes-agent/run_agent.py).

- One instance per session/profile
- Synchronous loop: LLM call → tool dispatch → result → next iteration (up to 90 iterations)
- Configurable model, personality, toolsets, and memory provider
- Maintains OpenAI-format message history
- Tracks token usage and cost per conversation

**Entry points:**
- `AIAgent.chat(message)` — simple string in/out interface
- `AIAgent.run_conversation(user_message, system_message, history)` — full interface returning dict with messages, usage, etc.

**Key constructor parameters:**
```python
AIAgent(
    model="...",                  # LLM model identifier
    max_iterations=90,            # Loop limit
    enabled_toolsets=[...],       # Whitelist toolsets
    disabled_toolsets=[...],      # Blacklist toolsets
    platform="cli",               # "cli", "telegram", "discord", etc.
    session_id="...",             # For session continuity
    skip_context_files=False,     # Skip injecting project .md files
    skip_memory=False,            # Skip memory injection
)
```

---

### 2. Subagents (Delegation)

Defined in [hermes-agent/tools/delegate_tool.py](hermes-agent/tools/delegate_tool.py).

Child `AIAgent` instances spawned on-demand by the primary agent to parallelize work without bloating the parent's context.

**Constraints:**
- Max 3 concurrent children
- Max delegation depth: 2 (parent → child; grandchildren rejected)
- Children never receive: `delegate_task`, `clarify`, `memory`, `send_message`, `execute_code`
- Child history is hidden from parent; only a summary is returned

**Usage (from within agent):**
```
/delegate goal="Build a web scraper for X" context="..." max_iterations=50 toolsets=["terminal","file","web"]
```

---

### 3. Mixture of Agents (MoA)

Defined in [hermes-agent/tools/mixture_of_agents_tool.py](hermes-agent/tools/mixture_of_agents_tool.py).

A parallel multi-LLM synthesis pattern for high-complexity reasoning tasks.

**Architecture:**
1. **Reference models** (run in parallel, temperature 0.6): Claude Opus, Gemini Pro, GPT-4, DeepSeek v3
2. **Aggregator model** (Claude Opus, temperature 0.4): synthesizes reference outputs into a single final answer

Requires at least 1 successful reference response (`MIN_SUCCESSFUL_REFERENCES = 1`).

---

### 4. Multiple Profiles

Defined in [hermes-agent/hermes_cli/profiles.py](hermes-agent/hermes_cli/profiles.py).

Each profile is an independent agent instance with isolated state:

- Own `HERMES_HOME/profiles/<name>/` directory
- Separate `state.db`, `MEMORY.md`, `SOUL.md`, sessions, skills, and cron jobs
- Separate gateway process (via Docker Compose service)
- All profiles share the same codebase; isolated only by directory and env vars

**Profile commands:**
```bash
hermes profile create <name>          # Fresh profile
hermes profile create <name> --clone  # Copy config + SOUL.md from current
hermes profile list
hermes profile use <name>             # Set sticky default
hermes -p <name> chat                 # One-off with specific profile
```

**Docker Compose multi-profile:**
```yaml
hermes-coder:
  <<: *hermes-base
  env_file: [.env, profiles/coder.env]
  environment:
    HERMES_PROFILE: coder
```

---

### 5. Scheduled Automation (Cron)

Defined in [hermes-agent/cron/jobs.py](hermes-agent/cron/jobs.py).

Background job execution via natural language scheduling. Each job spawns a fresh agent run.

```bash
hermes cron "send me a daily report at 9am"
hermes cron "search for new AI papers every Monday"
hermes cron list
hermes cron run <job-id>    # manual trigger
```

Jobs are stored in `~/.hermes/cron/jobs.json`. Output is saved to `~/.hermes/cron/output/{job_id}/{timestamp}.md` and delivered to any configured platform.

---

## Tools & Capabilities

Tool schemas and dispatch logic live in [hermes-agent/tools/registry.py](hermes-agent/tools/registry.py).

| Category | Tools |
|---|---|
| Terminal | Local, Docker, SSH, Modal, Daytona, Singularity backends |
| File | Read, write, patch, search (ripgrep) |
| Browser | Browserbase + Camoufox, screenshot capture |
| Web | Firecrawl scraping, Parallel web search |
| Code | Sandboxed Python/Node.js execution |
| Memory | Read/write MEMORY.md, Honcho, Hindsight, Mem0 |
| Delegation | Spawn subagents (delegate_tool) |
| MoA | Parallel multi-LLM synthesis |
| Cron | Create and manage scheduled jobs |
| MCP | Model Context Protocol integration |

---

## Memory System

Memory providers are pluggable via [hermes-agent/plugins/memory/](hermes-agent/plugins/memory/).

**Built-in (default):** `MEMORY.md` and `USER.md` with character limits (configurable via `memory_char_limit` / `user_char_limit`).

**Optional providers:**
- `honcho` — Cross-session user modeling with dialectic reasoning (see [optional-skills/autonomous-ai-agents/honcho/](hermes-agent/optional-skills/autonomous-ai-agents/honcho/))
- `hindsight` — Vector embeddings + semantic search (separate Docker container)
- `mem0`, `supermemory`, `openviking`, `retaindb`, `byterover`, `holographic`

**Config:**
```yaml
memory:
  provider: ''          # '' = built-in, 'honcho', etc.
  memory_char_limit: 2200
  user_char_limit: 1375
```

---

## Skills (Procedural Memory)

Skills are markdown files with prompts and examples, stored in [hermes-agent/skills/](hermes-agent/skills/) and [hermes-agent/optional-skills/](hermes-agent/optional-skills/).

Skills are injected as user messages (to preserve prompt caching), discoverable via `/skills`, and installable from the Skills Hub. The agent can also create new skills autonomously after completing complex tasks.

**Bundled skill domains:** research, devops, software-development, data-science, creative, domain-specific.

---

## Slash Commands

Centralized in [hermes-agent/hermes_cli/commands.py](hermes-agent/hermes_cli/commands.py) as a `CommandDef` registry. This single source of truth is shared across CLI, gateway, Telegram, Discord, Slack, and all other platforms.

---

## Configuration

**Config hierarchy:**

1. `~/.hermes/config.yaml` (or profile-specific override)
   - Model selection, agent settings (`max_turns`, `reasoning_effort`)
   - Memory provider, personality preset
   - Platform toolsets, web backend, skills config

2. `~/.hermes/.env` (or `profiles/<name>.env`)
   - API keys: `OPENROUTER_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`
   - Platform tokens: `TELEGRAM_BOT_TOKEN`, `DISCORD_TOKEN`, etc.
   - External services: `VPS_HOST`, `FIRECRAWL_PROXY_*`, `HINDSIGHT_LLM_*`

3. `docker-compose.yml` + overlays (`docker-compose.vps.yml`, `docker-compose.override.yml`)

**Key environment variables:**
```bash
HERMES_PROFILE=default              # Active profile
HERMES_HOME=/opt/data               # Data directory (container path)
HERMES_MAX_ITERATIONS=60            # Agent loop limit
TERMINAL_BACKEND=local              # local | docker | ssh | modal | daytona
HERMES_TIMEZONE=America/Los_Angeles # Timezone for cron
```

---

## Deployment

### Local development
```bash
make local-up       # Build + start full stack
make local-chat     # Interactive CLI
make local-down     # Stop stack
make local-restart  # Restart agent after config changes
```

### VPS deployment
```bash
make deploy         # rsync + docker compose up (via Tailscale)
make logs           # Follow agent logs
make shell          # Exec into agent container
make backup-now     # Manual backup snapshot
make restore ARGS="db latest"
```

### CI/CD

GitHub Actions workflow in [.github/workflows/deploy.yml](.github/workflows/deploy.yml):
- Triggers on push to `main`
- Joins Tailscale → rsync → `docker compose up` → Telegram notification

### Services stack
```
hermes-agent        # Primary agent + gateway
├─ hindsight        # Vector memory (ports 8888/9999)
├─ firecrawl-api    # Web scraping (port 3002)
├─ firecrawl-worker # Crawl job processor
├─ playwright       # Headless browser
├─ postgres         # Firecrawl + Hindsight DB
├─ redis            # Rate limiting / caching
└─ rabbitmq         # Job queue

VPS only:
├─ syncthing        # VPS ↔ MacBook file sync (Tailscale)
├─ litestream       # Continuous SQLite replication (10–30s cadence)
└─ backup           # Daily volume snapshots (30-day retention)
```

---

## LLM Providers

Primary: **OpenRouter** (200+ model routing). Fallbacks: Anthropic, OpenAI, Nous Portal, Z.AI, Kimi, MiniMax, and any OpenAI-compatible endpoint.

Multi-credential support via `credential_pool.py` for load balancing and failover.

Default model (config.yaml): `google/gemma-4-26b-a4b-it` via OpenRouter.
