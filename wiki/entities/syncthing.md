---
title: Syncthing
created: 2026-04-15
updated: 2026-04-15
type: entity
tags: [sync, operations, deployment, documentation, workflow]
sources: [raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-agents-architecture-2026-04-15.md]
---

# Syncthing

## Overview
Syncthing is an optional host-native file-sync mechanism on the VPS side of `[[hermes-stack]]`. It syncs non-canonical operator files under `/home/hermes/sync` to another machine, currently the MacBook, over Tailscale.

## What it syncs
Syncthing is no longer the source of truth for Hermes Stack wiki, shared SOUL, or shared skills. Those live in the repo:
- `wiki/`
- `soul/`
- `skills/`

Syncthing remains useful for profile exports, copied environment manifests, and other non-canonical working files that benefit from device-to-device sync.

## Why it matters
This keeps convenience sync separate from the repo-first operational model. The stack can be rebuilt from Git plus Hetzner VPS backups without relying on Syncthing state.

## Operational notes
- the UI is exposed on localhost port 8384 and published to the tailnet through Tailscale Serve on `:9445`
- the VPS service is `syncthing@hermes.service`
- folder paths in the UI are host paths such as `/home/hermes/sync`, not Docker paths like `/sync`

## Related pages
- [[hermes-stack]]
- [[shared-soul]]
- [[profile-separation]]
- [[workspace-mapping]]
