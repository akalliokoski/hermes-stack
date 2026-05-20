---
title: Hermes Stack
created: 2026-04-15
updated: 2026-04-15
type: entity
tags: [repo, deployment, operations, default-profile, docker, systemd, documentation]
sources: [raw/transcripts/hermes-stack-initial-context-2026-04-15.md, raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-provision-profile-script-2026-04-15.md, raw/articles/hermes-stack-agents-architecture-2026-04-15.md]
---

# Hermes Stack

## Overview
`hermes-stack` is the deployment repo at `/home/hermes/work/hermes-stack`. It is the current main priority for the default Hermes profile and acts as the operational control plane for the VPS deployment.

## What it contains
The repo defines the deployment layer around [[hermes-agent]]:
- setup and operations guidance in `SETUP.md`
- canonical profile provisioning in `scripts/provision-profile.sh`
- compose files for supporting services
- bootstrap, reset, restore, and deploy scripts for day-to-day operations

## Operational model
The repo keeps concerns separate:
- [[hermes-agent]] runs natively on the VPS under systemd as user `hermes`
- Docker Compose manages supporting services such as Firecrawl, Hindsight, Litestream, backup, and [[syncthing]]
- profile creation and update are standardized through [[provisioning-flow]]
- profile workspaces are mapped through [[workspace-mapping]]

## Why it matters now
For the default profile, this repo is the main active surface area. Questions about deployment, bootstrap, sync, memory service wiring, profile creation, and runtime behavior should usually start here.

## Notable documented behaviors
- The stack uses native Hermes plus Docker-backed shell sandboxes rather than running the main agent as a Compose container
- Shared instructions are centralized through [[shared-soul]]
- Profile runtime separation is described by [[profile-separation]] and enforced by provisioning
- The wiki itself is intended to sync through [[syncthing]] as part of the `.hermes` tree

## Related pages
- [[hermes-agent]]
- [[provisioning-flow]]
- [[workspace-mapping]]
- [[profile-separation]]
- [[shared-soul]]
- [[syncthing]]
- [[hindsight-memory]]
