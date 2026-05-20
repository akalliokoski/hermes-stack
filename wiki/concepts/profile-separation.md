---
title: Profile Separation
created: 2026-04-15
updated: 2026-04-15
type: concept
tags: [profile, multi-profile, default-profile, workspace, config, memory, hindsight, workflow]
sources: [raw/transcripts/hermes-stack-initial-context-2026-04-15.md, raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-provision-profile-script-2026-04-15.md, raw/articles/hermes-stack-agents-architecture-2026-04-15.md]
---

# Profile Separation

## Definition
Profile separation is the pattern of keeping Hermes profiles distinct where state matters, while still sharing selected common instruction sources and infrastructure.

## What is isolated
In the current stack, each profile gets its own:
- workspace under `/home/hermes/work/<profile>` through [[workspace-mapping]]
- Hermes profile directory and rendered `SOUL.md`
- Hindsight `bankId` through [[hindsight-memory]]
- profile-local config, sessions, and runtime state

## What is shared
Profiles can still share:
- common instruction sources through [[shared-soul]]
- the single `[[hindsight-memory]]` service endpoint
- the same `[[hermes-stack]]` deployment repo and surrounding infrastructure
- the shared wiki vault when that is operationally more useful than splitting knowledge by profile

## Why this arrangement makes sense
This balances reuse with isolation:
- reuse: durable behavior is maintained once and rendered where needed
- isolation: memory, workspace, and profile-local config do not bleed together accidentally
- flexibility: the default profile can prioritize `[[hermes-stack]]` without forcing every other profile to share the same mission focus

## Operational rule
If the thing is behavior or guidance, consider [[shared-soul]]. If the thing is runtime state or memory, keep it profile-local.

## Related pages
- [[shared-soul]]
- [[workspace-mapping]]
- [[provisioning-flow]]
- [[hindsight-memory]]
- [[hermes-stack]]
- [[hermes-agent]]
