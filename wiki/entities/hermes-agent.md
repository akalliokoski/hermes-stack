---
title: Hermes Agent
created: 2026-04-15
updated: 2026-04-15
type: entity
tags: [agent, operations, profile, config, memory, documentation, workflow]
sources: [raw/transcripts/hermes-stack-initial-context-2026-04-15.md, raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-agents-architecture-2026-04-15.md]
---

# Hermes Agent

## Overview
`hermes-agent` is the core runtime behind the stack. In this deployment, it runs natively on the VPS under systemd as user `hermes`, while shell execution is sandboxed through Docker-backed terminal commands.

## Relevant architectural facts
- Hermes supports multiple profiles with isolated state under `HERMES_HOME/profiles/<name>/`
- Profile-local state includes config, sessions, skills, cron data, and `SOUL.md`
- Optional memory backends include Hindsight, which the current stack uses via [[hindsight-memory]]
- The deployment repo `[[hermes-stack]]` layers VPS-specific operational choices on top of Hermes core behavior

## In this stack specifically
The current stack turns Hermes profile support into an operational pattern:
- [[provisioning-flow]] creates or updates named profiles
- [[workspace-mapping]] ensures each profile gets its own writable `/workspace`
- [[shared-soul]] lets profiles share common instructions without sharing all state
- [[profile-separation]] describes what is intentionally isolated and what is shared

## Practical implication
When diagnosing behavior, separate Hermes core capabilities from deployment-layer choices in `[[hermes-stack]]`. That distinction explains why some behavior comes from upstream Hermes while other behavior comes from repo scripts and docs.

## Related pages
- [[hermes-stack]]
- [[profile-separation]]
- [[shared-soul]]
- [[provisioning-flow]]
- [[workspace-mapping]]
- [[hindsight-memory]]
