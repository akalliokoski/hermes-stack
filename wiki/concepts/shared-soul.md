---
title: Shared SOUL
created: 2026-04-15
updated: 2026-04-15
type: concept
tags: [soul, multi-profile, profile, default-profile, config, workflow, documentation]
sources: [raw/transcripts/hermes-stack-initial-context-2026-04-15.md, raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-provision-profile-script-2026-04-15.md]
---

# Shared SOUL

## Definition
Shared SOUL is the instruction layout under `~/.hermes/shared/soul/` that allows Hermes profiles to share a common behavioral base while still keeping per-profile overrides.

## Current layout
- `base.md` contains instructions shared by every profile
- `profiles/<name>.md` contains profile-specific additions or overrides
- [[provisioning-flow]] renders each profile's final `SOUL.md` from those sources
- rerendering all profiles is supported through the sync-all-souls mode documented in `[[hermes-stack]]`

## Why it matters
This setup gives the user one place to maintain common behavior while still supporting [[profile-separation]]. It reduces duplication without forcing shared runtime state.

## Current default-profile use
The shared base now carries durable guidance about profile separation, while the default override records that `[[hermes-stack]]` is the current main operational priority. That is the intended pattern: cross-profile rules in base, mission focus in the profile override.

## Operational rule of thumb
Put broad, durable cross-profile guidance here. Keep profile-local mission focus in the matching override unless the guidance truly applies everywhere.

## Related pages
- [[profile-separation]]
- [[provisioning-flow]]
- [[hermes-stack]]
- [[hermes-agent]]
