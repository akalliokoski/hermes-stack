# Makefile – common operations for the Hermes stack
# Run from the repo root on VPS (or via deploy.sh from MacBook).
#
# Usage:
#   make up             start (or restart) the full stack
#   make down           stop the stack
#   make restart        restart only the hermes-agent (e.g. after config change)
#   make deploy         push & redeploy from MacBook (runs deploy.sh)
#   make status         show container status
#   make logs           tail hermes-agent logs  (Ctrl-C to stop)
#   make logs-all       tail all service logs
#   make shell          open a bash shell inside hermes-agent
#   make hermes         interactive hermes chat   (alias: make chat)
#   make hermes ARGS="skills"        run a specific hermes subcommand
#   make hermes ARGS="profile list"  run with arguments
#   make backup         back up all Docker volumes now
#   make clean          remove stopped containers and dangling images

.PHONY: up down restart deploy status logs logs-all shell hermes chat backup clean \
        local-up local-down local-restart local-chat local-logs local-status local-build

COMPOSE         = docker compose
LOCAL_COMPOSE   = docker compose -f docker-compose.local.yml
CONTAINER       = hermes_agent
ARGS            ?=

# ── Stack lifecycle ────────────────────────────────────────────────────────────

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

clean:
	docker container prune -f
	docker image prune -f

# ── Local dev (no syncthing / tailscale) ──────────────────────────────────────
# Workflow:
#   make local-up      start all services (builds image if needed)
#   make local-chat    open interactive hermes chat (requires local-up)
#   make local-down    stop and remove containers

local-build:
	$(LOCAL_COMPOSE) build hermes-agent

local-up:
	@mkdir -p sync
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
