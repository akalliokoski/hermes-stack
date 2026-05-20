---
title: Provisioning Flow
created: 2026-04-15
updated: 2026-04-15
type: concept
tags: [workflow, automation, profile, multi-profile, config, soul, hindsight, workspace]
sources: [raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-provision-profile-script-2026-04-15.md]
---

# Provisioning Flow

## Definition
Provisioning flow is the standardized create-or-update path for Hermes profiles in `[[hermes-stack]]`, centered on `scripts/provision-profile.sh` and the helper command `provision-profile`.

## Inputs and modes
The script supports:
- `--profile <name>` for create-or-update of one profile
- optional `--telegram-bot-token <token>` for profile-local bot credentials
- `--gateway auto|skip|required` for gateway install behavior
- `--sync-all-souls` for rerendering all profile `SOUL.md` files from [[shared-soul]] sources

## What the flow does
For a named profile, provisioning:
- creates the profile if needed
- creates a profile-local workspace via [[workspace-mapping]]
- updates terminal config to mount the correct workspace at `/workspace`
- writes profile-local git include config
- writes Hindsight config with a profile-specific bank via [[hindsight-memory]]
- renders `SOUL.md` from [[shared-soul]]
- installs and starts a system gateway when privilege is available

## Important operational detail
The script is intentionally rerunnable. It is not a one-shot bootstrap helper; it is the canonical path for keeping profile setup consistent over time.

## Why it matters
This is the key bridge between conceptual [[profile-separation]] and actual filesystem/runtime enforcement.

## Related pages
- [[hermes-stack]]
- [[shared-soul]]
- [[workspace-mapping]]
- [[hindsight-memory]]
- [[profile-separation]]
