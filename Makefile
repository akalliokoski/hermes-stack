# Makefile – common operations for the Hermes stack
# Run from the repo root on VPS (or via deploy.sh from MacBook).
# Full docs: SETUP.md
#
# VPS stack:
#   make up                           start full VPS stack (syncthing + tailscale included)
#   make down                         stop the stack
#   make restart                      restart hermes-agent (e.g. after config change)
#   make deploy                       push & redeploy from MacBook (runs deploy.sh)
#   make status                       show container status
#   make logs                         tail hermes-agent logs  (Ctrl-C to stop)
#   make logs-all                     tail all service logs
#   make shell                        open a bash shell inside hermes-agent
#   make chat                         interactive hermes chat
#   make hermes ARGS="skills"         run a hermes subcommand
#   make hermes ARGS="profile list"   run with arguments
#
# Backup & restore (VPS):
#   make backup                       back up non-hermes volumes (postgres, redis, …)
#   make backup-now                   trigger immediate hermes_data backup
#   make snapshots                    list available restore points
#   make restore ARGS="list"          same as snapshots
#   make restore ARGS="db latest"     restore state.db via Litestream
#   make restore ARGS="db 2026-04-05T21:00:00"  point-in-time restore
#   make restore ARGS="file memories/MEMORY.md <tarball>"  single-file restore
#   make restore ARGS="volume <tarball>"         full volume restore
#
#   make clean                        remove stopped containers and dangling images
#   make vps-clean-old                remove legacy /opt/clawctl data from VPS (first deploy only)
#
# Local dev (docker-compose.override.yml applied automatically):
#   make local-up                     start local stack (no syncthing/tailscale)
#   make local-down                   stop local stack
#   make local-restart                restart hermes-agent only
#   make local-chat                   open interactive hermes chat
#   make local-backup-now             trigger immediate backup
#   make local-snapshots              list available restore points

.PHONY: up down restart deploy status logs logs-all shell hermes chat backup clean vps-clean-old \
        local-up local-down local-restart local-chat local-logs local-status local-build \
        backup-now local-backup-now snapshots local-snapshots restore

COMPOSE       = docker compose -f docker-compose.yml -f docker-compose.vps.yml
LOCAL_COMPOSE = docker compose                          # auto-merges docker-compose.override.yml
CONTAINER     = hermes_agent
ARGS          ?=

# ── VPS stack lifecycle ────────────────────────────────────────────────────────

up:
	$(COMPOSE) up -d --remove-orphans

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart hermes-agent

deploy:
	bash deploy.sh

# ── Observability ──────────────────────────────────────────────────────────────

status:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f hermes-agent

logs-all:
	$(COMPOSE) logs -f

# ── Interactive access ─────────────────────────────────────────────────────────

shell:
	docker exec -it $(CONTAINER) bash

# Run any hermes command.  No ARGS = interactive chat.
hermes:
	docker exec -it $(CONTAINER) hermes $(ARGS)

chat: hermes   # convenience alias

# ── Maintenance ────────────────────────────────────────────────────────────────

backup:
	bash scripts/backup-volumes.sh

backup-now:
	docker exec $$($(COMPOSE) ps -q backup) backup

snapshots:
	bash scripts/restore.sh list

restore:
	bash scripts/restore.sh $(ARGS)

clean:
	docker container prune -f
	docker image prune -f

# Remove legacy OpenClaw/clawctl data from the VPS (one-time, before first deploy)
vps-clean-old:
	@VPS_HOST=$$(grep -E '^VPS_HOST=' .env | cut -d= -f2); \
	  ssh "$${VPS_HOST:?Set VPS_HOST in .env}" 'rm -rf /opt/clawctl && echo "✓ Old clawctl data removed"'

# ── Local dev ─────────────────────────────────────────────────────────────────
# docker-compose.override.yml is merged automatically – no extra -f needed.
# Workflow:
#   make local-up      build image + start all services
#   make local-chat    open interactive hermes chat (requires local-up)
#   make local-down    stop and remove containers

local-build:
	$(LOCAL_COMPOSE) build hermes-agent

local-up:
	@mkdir -p sync backups
	$(LOCAL_COMPOSE) up -d --build --remove-orphans

local-down:
	$(LOCAL_COMPOSE) down

local-restart:
	$(LOCAL_COMPOSE) restart hermes-agent

local-status:
	$(LOCAL_COMPOSE) ps

local-logs:
	$(LOCAL_COMPOSE) logs -f hermes-agent

local-chat:
	docker exec -it $(CONTAINER) hermes $(ARGS)

local-backup-now:
	docker exec $$($(LOCAL_COMPOSE) ps -q backup) backup

local-snapshots:
	bash scripts/restore.sh list
