# Makefile – common operations for the Hermes stack.
#
# hermes-agent runs natively on the VPS under systemd (user: hermes).
# Docker Compose only runs the auxiliary services (firecrawl, hindsight,
# litestream, backup, syncthing). See SETUP.md for the full topology.
#
# VPS:
#   make up                           start support services
#   make down                         stop support services
#   make deploy                       push & redeploy from MacBook (runs deploy.sh)
#   make status                       show container status
#   make logs                         tail hermes-gateway logs via ssh
#   make logs-all                     tail all compose service logs
#   make restart                      restart hermes-gateway on the VPS
#   make chat                         interactive hermes chat on the VPS
#   make shell                        bash shell on the VPS as the hermes user
#   make hermes ARGS="skills"         run a hermes subcommand
#   make update-agent                 `hermes update` on the VPS (pulls new release)
#
# Backup & restore (VPS):
#   make backup-now                   trigger immediate .hermes tarball
#   make snapshots                    list available restore points
#   make restore ARGS="..."           see scripts/restore.sh
#
# Local dev (MacBook, docker-compose.override.yml auto-applied):
#   make local-up                     start local support services
#   make local-down                   stop them
#   make local-chat                   `hermes chat` against ~/.hermes
#   make local-update-agent           `hermes update` locally

.PHONY: up down deploy status logs logs-all restart chat shell hermes \
        update-agent backup-now snapshots restore clean \
        local-up local-down local-chat local-status local-logs \
        local-backup-now local-snapshots local-update-agent

COMPOSE       = docker compose -f docker-compose.yml -f docker-compose.vps.yml
LOCAL_COMPOSE = docker compose                          # auto-merges docker-compose.override.yml
ARGS          ?=

VPS_HOST := $(shell grep -E '^VPS_HOST=' .env 2>/dev/null | cut -d= -f2)

# ── VPS stack lifecycle ────────────────────────────────────────────────────────

up:
	$(COMPOSE) up -d --remove-orphans

down:
	$(COMPOSE) down

deploy:
	bash deploy.sh

# ── Observability ──────────────────────────────────────────────────────────────

status:
	@if [ -n "$(VPS_HOST)" ]; then ssh $(VPS_HOST) "systemctl status hermes-gateway --no-pager; cd /opt/hermes && docker compose -f docker-compose.yml -f docker-compose.vps.yml ps"; else echo "Set VPS_HOST in .env"; fi

logs:
	ssh -t $(VPS_HOST) 'journalctl -u hermes-gateway -f'

logs-all:
	ssh -t $(VPS_HOST) 'cd /opt/hermes && docker compose -f docker-compose.yml -f docker-compose.vps.yml logs -f'

# ── Hermes agent control (host-installed, systemd-managed) ────────────────────

restart:
	ssh $(VPS_HOST) 'sudo systemctl restart hermes-gateway'

chat:
	ssh -t $(VPS_HOST) 'sudo -iu hermes hermes chat $(ARGS)'

shell:
	ssh -t $(VPS_HOST) 'sudo -iu hermes bash'

hermes:
	ssh -t $(VPS_HOST) 'sudo -iu hermes hermes $(ARGS)'

update-agent:
	ssh -t $(VPS_HOST) 'sudo -iu hermes hermes update && sudo systemctl restart hermes-gateway'

# ── Maintenance ────────────────────────────────────────────────────────────────

backup-now:
	ssh $(VPS_HOST) 'cd /opt/hermes && docker exec $$(docker compose -f docker-compose.yml -f docker-compose.vps.yml ps -q backup) backup'

snapshots:
	bash scripts/restore.sh list

restore:
	bash scripts/restore.sh $(ARGS)

clean:
	docker container prune -f
	docker image prune -f

# ── Local dev ─────────────────────────────────────────────────────────────────
# docker-compose.override.yml is merged automatically – no extra -f needed.
# hermes runs natively via `hermes chat` against ~/.hermes.

local-up:
	@mkdir -p backups
	$(LOCAL_COMPOSE) up -d --remove-orphans

local-down:
	$(LOCAL_COMPOSE) down

local-status:
	$(LOCAL_COMPOSE) ps

local-logs:
	$(LOCAL_COMPOSE) logs -f

local-chat:
	hermes chat $(ARGS)

local-update-agent:
	hermes update

local-backup-now:
	docker exec $$($(LOCAL_COMPOSE) ps -q backup) backup

local-snapshots:
	bash scripts/restore.sh list
