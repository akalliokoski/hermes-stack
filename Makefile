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

.PHONY: up down restart deploy status logs logs-all shell hermes chat backup clean

COMPOSE   = docker compose
CONTAINER = hermes_agent
ARGS      ?=

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
