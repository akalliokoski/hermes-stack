# Profile cron ticker services

This repo can manage dedicated host-level systemd tickers for profile-local Hermes cron jobs without modifying Hermes Agent itself.

## Why

Profile-local cron state lives under each profile's `HERMES_HOME`, so a generic gateway or a one-off foreground shell is not a reliable long-term driver for unattended jobs. A dedicated ticker service keeps `hermes cron tick --accept-hooks` running against the intended profile home.

## Source of truth

Managed profiles are listed in:

- `config/profile-cron-tickers.txt`

One profile name per line. Blank lines and `# comments` are ignored.

The default profile is intentionally not listed right now so it stays more stable unless explicitly opted in.

## Installed runtime pieces

Remote deploy installs:

- `scripts/hermes-cron-tick@.service`
- `scripts/run-profile-cron-tick.sh`

Each configured profile gets an instance such as:

- `hermes-cron-tick@aaltoni.service`

The helper resolves the correct profile-local `HERMES_HOME` and runs the stock Hermes command:

- `hermes cron tick --accept-hooks`

## Deployment behavior

`scripts/remote-deploy.sh` will:

1. install/update the template unit and helper script
2. `systemctl daemon-reload`
3. enable/restart ticker instances for configured profiles that exist
4. disable ticker instances that are no longer listed in `config/profile-cron-tickers.txt`

## Verification

On the VPS:

```bash
systemctl status hermes-cron-tick@aaltoni.service --no-pager
journalctl -u hermes-cron-tick@aaltoni.service -n 50 --no-pager
```

If a profile's cron jobs still do not execute, check profile-local prerequisites first:

- `~/.hermes/profiles/<name>/auth.json`
- `~/.hermes/profiles/<name>/.env`
- `~/.hermes/profiles/<name>/cron/jobs.json`
- `~/.hermes/profiles/<name>/sessions/session_cron_*.json`
