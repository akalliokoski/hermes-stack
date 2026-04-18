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
#   make add-profile PROFILE=<name>   create/update a profile on the VPS via scripts/provision-profile.sh
#   make sync-souls                  rerender SOUL.md for default + all named profiles on the VPS
#   make sync-profiles               rewrite git/hindsight/SOUL config for default + all named profiles on the VPS
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
#   make detect-env                   print the detected Hermes environment id
#   make sync-env                     render local default config + ENVIRONMENT.md for this machine
#   make sync-profiles-local          normalize local default + named profiles for this machine
#   make local-chat                   `hermes chat` against ~/.hermes
#   make local-update-agent           `hermes update` locally
#   make local-setup-hindsight        write hindsight/config.json locally

.PHONY: up down deploy status logs logs-all restart chat shell hermes \
        update-agent backup-now snapshots restore clean add-profile sync-souls sync-profiles setup-hindsight \
        detect-env sync-env sync-profiles-local local-up local-down local-chat local-status local-logs \
        local-backup-now local-snapshots local-update-agent local-setup-hindsight

COMPOSE       = docker compose -f docker-compose.yml -f docker-compose.vps.yml
LOCAL_COMPOSE = docker compose                          # auto-merges docker-compose.override.yml
ARGS          ?=
SERVICE_MODE  ?= auto

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
	@if [ -n "$(VPS_HOST)" ]; then ssh $(VPS_HOST) "systemctl status hermes-gateway hermes-dashboard --no-pager; cd /opt/hermes && docker compose -f docker-compose.yml -f docker-compose.vps.yml ps; tailscale serve status --json"; else echo "Set VPS_HOST in .env"; fi

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
# Write/repair Hindsight config on the VPS via the canonical provisioning script.
# Each profile gets its own bank so memories are isolated — see add-profile below.

setup-hindsight:
	@if [ -n "$(PROFILE)" ]; then \
	  ssh $(VPS_HOST) "cd /opt/hermes && sudo bash scripts/provision-profile.sh --profile $(PROFILE) --gateway skip" ; \
	else \
	  ssh $(VPS_HOST) 'cd /opt/hermes && sudo bash scripts/provision-profile.sh --profile default --gateway skip' ; \
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

detect-env:
	@bash scripts/detect-env.sh

sync-env:
	@ENV_ID="$$(bash scripts/detect-env.sh)"; \
	bash scripts/ensure-python-yaml.sh; \
	mkdir -p "$$HOME/.hermes"; \
	python3 scripts/render-config.py --env-id "$$ENV_ID" --target-home "$$HOME" --profile default --output "$$HOME/.hermes/config.yaml"; \
	python3 scripts/render-environment-context.py --env-id "$$ENV_ID" --profile default --profile-home "$$HOME/.hermes" --config-path "$$HOME/.hermes/config.yaml" --output "$$HOME/.hermes/ENVIRONMENT.md"; \
	echo "✓ Rendered local default config and ENVIRONMENT.md for $$ENV_ID"

# ── Profile management ────────────────────────────────────────────────────────
# Create/update a hermes profile on the VPS via scripts/provision-profile.sh.
# This is also the same script you can run directly on the VPS (or from Hermes chat)
# after deploy: `bash /opt/hermes/scripts/provision-profile.sh --profile <name>`.
#
# Usage:
#   make add-profile PROFILE=myprofile
#   make add-profile PROFILE=myprofile TELEGRAM_BOT_TOKEN=***
#   make sync-souls
#   make sync-profiles
PROFILE ?=
TELEGRAM_BOT_TOKEN ?=

add-profile:
	@[ -n "$(PROFILE)" ] || { echo "ERROR: PROFILE is required"; exit 1; }
	@echo "→ Provisioning profile '$(PROFILE)' on $(VPS_HOST)"
	ssh $(VPS_HOST) "cd /opt/hermes && sudo bash scripts/provision-profile.sh --profile $(PROFILE)$(if $(TELEGRAM_BOT_TOKEN), --telegram-bot-token '$(TELEGRAM_BOT_TOKEN)',)"


sync-souls:
	@echo "→ Rerendering shared SOUL.md files on $(VPS_HOST)"
	ssh $(VPS_HOST) 'cd /opt/hermes && sudo bash scripts/provision-profile.sh --sync-all-souls'

sync-profiles:
	@echo "→ Rewriting profile config for default + all named profiles on $(VPS_HOST)"
	ssh $(VPS_HOST) 'cd /opt/hermes && sudo bash scripts/provision-profile.sh --sync-all-profiles --gateway skip'

sync-profiles-local:
	@ENV_ID="$$(bash scripts/detect-env.sh)"; \
	bash scripts/ensure-python-yaml.sh; \
	WORK_ROOT="$$(python3 scripts/render-config.py --env-id "$$ENV_ID" --target-home "$$HOME" --print-meta env.work_root)"; \
	HINDSIGHT_API_URL="$$(python3 scripts/render-config.py --env-id "$$ENV_ID" --target-home "$$HOME" --print-service-url hindsight --service-mode "$(SERVICE_MODE)")"; \
	mkdir -p "$$HOME/.hermes"; \
	HERMES_ENV_ID="$$ENV_ID" HERMES_SERVICE_MODE="$(SERVICE_MODE)" HERMES_USER="$$(id -un)" HERMES_HOME="$$HOME/.hermes" WORK_ROOT="$$WORK_ROOT" HINDSIGHT_API_URL="$$HINDSIGHT_API_URL" bash scripts/provision-profile.sh --sync-all-profiles --gateway skip

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
	@ENV_ID="$$(bash scripts/detect-env.sh)"; \
	bash scripts/ensure-python-yaml.sh; \
	API_URL="$$(python3 scripts/render-config.py --env-id "$$ENV_ID" --target-home "$$HOME" --print-service-url hindsight --service-mode "$(SERVICE_MODE)")"; \
	mkdir -p $(HOME)/.hermes/hindsight; \
	printf '{"mode":"local_external","api_url":"%s","bank_id":"hermes-default","recall_budget":"mid","memory_mode":"hybrid","auto_recall":true,"auto_retain":true,"retain_every_n_turns":1,"retain_async":true}\n' "$$API_URL" > $(HOME)/.hermes/hindsight/config.json; \
	chmod 600 $(HOME)/.hermes/hindsight/config.json; \
	echo "✓ Hindsight configured locally for $$ENV_ID (bank: hermes-default, service mode: $(SERVICE_MODE))"
