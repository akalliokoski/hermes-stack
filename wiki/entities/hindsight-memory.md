---
title: Hindsight Memory
created: 2026-04-15
updated: 2026-04-15
type: entity
tags: [memory, hindsight, profile, multi-profile, operations, config]
sources: [raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-provision-profile-script-2026-04-15.md, raw/articles/hermes-stack-agents-architecture-2026-04-15.md]
---

# Hindsight Memory

## Overview
Hindsight is the vector-memory service used by the current stack. In this deployment it is exposed locally at `http://127.0.0.1:8888` with a UI on `127.0.0.1:9999`, and Hermes profiles use it as the active memory backend.

## Isolation model
The stack does not create one Hindsight service per profile. Instead:
- all profiles share the same Hindsight service endpoint
- each profile writes its own `hindsight/config.json`
- each config uses a profile-specific `bankId` such as `hermes-default` or `hermes-<name>`

This is the memory half of [[profile-separation]].

## Operational notes
- provisioning writes the Hindsight config during [[provisioning-flow]]
- Tailscale can expose the service via `/memory/` and `/memory-ui/`
- the stack docs treat this as shared infrastructure with isolated logical banks

## Related pages
- [[profile-separation]]
- [[provisioning-flow]]
- [[hermes-agent]]
- [[hermes-stack]]
