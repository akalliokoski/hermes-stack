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
#   make add-profile PROFILE=<name>   create a new profile with its own workspace
#   make setup-hindsight              write hindsight/config.json for default profile
#   make setup-hindsight PROFILE=<n>  write hindsight/config.json for a named profile
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
#   make local-setup-hindsight        write hindsight/config.json locally

.PHONY: up down deploy status logs logs-all restart chat shell hermes \
        update-agent backup-now snapshots restore clean add-profile setup-hindsight \
        local-up local-down local-chat local-status local-logs \
        local-backup-now local-snapshots local-update-agent local-setup-hindsight

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

# ── Hindsight memory backend ──────────────────────────────────────────────────
# Write the default-profile hindsight config on the VPS (run once after deploy).
# Each profile gets its own bank so memories are isolated — see add-profile below.

setup-hindsight:
	@if [ -n "$(PROFILE)" ]; then \
	  ssh $(VPS_HOST) 'sudo -iu hermes bash -c " \
	    mkdir -p /home/hermes/.hermes/profiles/$(PROFILE)/hindsight && \
	    printf '"'"'{"hindsightApiUrl":"http://127.0.0.1:8888","bankId":"hermes-$(PROFILE)","autoRecall":true,"autoRetain":true}\n'"'"' \
	      > /home/hermes/.hermes/profiles/$(PROFILE)/hindsight/config.json && \
	    chmod 600 /home/hermes/.hermes/profiles/$(PROFILE)/hindsight/config.json"' ; \
	  echo "✓ Hindsight configured for profile '$(PROFILE)' (bank: hermes-$(PROFILE))" ; \
	else \
	  ssh $(VPS_HOST) 'sudo -iu hermes bash -c " \
	    mkdir -p /home/hermes/.hermes/hindsight && \
	    printf '"'"'{"hindsightApiUrl":"http://127.0.0.1:8888","bankId":"hermes-default","autoRecall":true,"autoRetain":true}\n'"'"' \
	      > /home/hermes/.hermes/hindsight/config.json && \
	    chmod 600 /home/hermes/.hermes/hindsight/config.json"' ; \
	  echo "✓ Hindsight configured for default profile (bank: hermes-default)" ; \
	fi

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

# ── Profile management ────────────────────────────────────────────────────────
# Create a new hermes profile with its own isolated workspace.
# Usage:  make add-profile PROFILE=myprofile TELEGRAM_BOT_TOKEN=123:ABC...
#
# What it does:
#   1. Creates /home/hermes/work/<profile> on the VPS
#   2. Creates the hermes profile (copies default config)
#   3. Updates the profile's docker_volumes to use its own workspace
#   4. Writes TELEGRAM_BOT_TOKEN to the profile's .env
#   5. Installs + starts the gateway systemd unit for the profile
PROFILE ?=
TELEGRAM_BOT_TOKEN ?=

add-profile:
	@[ -n "$(PROFILE)" ] || { echo "ERROR: PROFILE is required. Usage: make add-profile PROFILE=<name> TELEGRAM_BOT_TOKEN=<token>"; exit 1; }
	@[ -n "$(TELEGRAM_BOT_TOKEN)" ] || { echo "ERROR: TELEGRAM_BOT_TOKEN is required. Usage: make add-profile PROFILE=<name> TELEGRAM_BOT_TOKEN=<token>"; exit 1; }
	@echo "→ Creating profile '$(PROFILE)' on $(VPS_HOST)"
	ssh $(VPS_HOST) 'sudo install -d -o hermes -g hermes -m 755 /home/hermes/work/$(PROFILE)'
	ssh $(VPS_HOST) 'sudo -iu hermes hermes profile create $(PROFILE)'
	ssh $(VPS_HOST) 'sudo -iu hermes sed -i "s|/home/hermes/work/default:/workspace|/home/hermes/work/$(PROFILE):/workspace|g" /home/hermes/.hermes/profiles/$(PROFILE)/config.yaml'
	ssh $(VPS_HOST) 'sudo -iu hermes bash -c "echo TELEGRAM_BOT_TOKEN=$(TELEGRAM_BOT_TOKEN) > /home/hermes/.hermes/profiles/$(PROFILE)/.env && chmod 600 /home/hermes/.hermes/profiles/$(PROFILE)/.env"'
	ssh $(VPS_HOST) 'sudo -iu hermes hermes -p $(PROFILE) gateway install --system --run-as-user hermes'
	ssh $(VPS_HOST) 'sudo hermes -p $(PROFILE) gateway start --system'
	ssh $(VPS_HOST) 'sudo -iu hermes bash -c " \
	  mkdir -p /home/hermes/.hermes/profiles/$(PROFILE)/hindsight && \
	  printf '"'"'{"hindsightApiUrl":"http://127.0.0.1:8888","bankId":"hermes-$(PROFILE)","autoRecall":true,"autoRetain":true}\n'"'"' \
	    > /home/hermes/.hermes/profiles/$(PROFILE)/hindsight/config.json && \
	  chmod 600 /home/hermes/.hermes/profiles/$(PROFILE)/hindsight/config.json"'
	@echo "✓ Profile '$(PROFILE)' ready — gateway running as hermes-gateway-$(PROFILE).service, Hindsight bank: hermes-$(PROFILE)"

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

local-setup-hindsight:
	mkdir -p $(HOME)/.hermes/hindsight
	printf '{"hindsightApiUrl":"http://127.0.0.1:8888","bankId":"hermes-default","autoRecall":true,"autoRetain":true}\n' \
	  > $(HOME)/.hermes/hindsight/config.json
	chmod 600 $(HOME)/.hermes/hindsight/config.json
	@echo "✓ Hindsight configured locally (bank: hermes-default)"
