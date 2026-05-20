---
title: Default Hermes multiprofile simplification audit
created: 2026-05-08
updated: 2026-05-08
type: query
tags: [hermes, hermes-stack, profile, gateway, multi-profile, audit, default-profile]
---

# Default Hermes multiprofile simplification audit

## Question
Has upstream Hermes Agent improved enough that hermes-stack can simplify its profile and gateway management on this VPS?

## Findings
- Upstream Hermes now treats profiles as first-class and explicitly documents isolated profile homes under `~/.hermes/profiles/<name>/`.
- Native per-profile gateway services are now part of the intended model:
  - default profile -> `hermes-gateway`
  - named profile -> `hermes-gateway-<profile>`
- Native per-profile service install flow exists and is already what hermes-stack uses for named profiles: `hermes -p <profile> gateway install --system --run-as-user <user>`.
- Current upstream docs/code also show profile-aware gateway status, profile aliases, sticky active profile support, token-lock protection, and better per-profile HOME isolation.
- Upstream git history indicates continued multi-profile improvements beyond the installed version on this VPS, including `hermes gateway list`.

## What should stay in hermes-stack
These are still stack policy, not obsolete workarounds:
- shared SOUL base plus per-profile override rendering
- shared cross-profile skills via `skills.external_dirs`
- per-profile Hindsight `bank_id` conventions such as `hermes-<profile>`
- workspace and terminal wiring
- repo-owned systemd hardening and deployment orchestration
- separate `.env`, memory, sessions, and gateway state per profile

## What may be simplifiable later
- docs that still imply named-profile gateways are unusually fragile
- custom status or discovery wrappers that duplicate modern Hermes profile/gateway commands
- historical gateway-specific special casing where upstream now already handles service naming and profile awareness
- default-vs-named gateway lifecycle differences, after updating Hermes and re-checking the live command surface

## VPS-specific observations at audit time
- Installed Hermes before update attempt: `v0.12.0 (2026.4.30)`.
- `hermes --version` reported the local checkout was 254 commits behind and recommended `hermes update`.
- `hermes gateway --help` on the installed version did not yet expose `gateway list`, even though the local upstream git history included that feature.
- Live gateway state was mixed:
  - `hermes-gateway.service` active for default profile
  - `hermes-gateway-gemma.service` active for `gemma`
  - `ai-lab` gateway appeared to be running manually rather than as an installed unit
- Hermes gateway status also warned that some installed unit definitions were outdated.

## Recommended next pass
1. Update Hermes successfully and re-check the available gateway/profile commands.
2. Refresh or reinstall outdated gateway units where Hermes recommends it.
3. Audit `scripts/provision-profile.sh` for logic that only exists because older Hermes multi-profile support used to be weaker.
4. Keep the isolation model; simplify wrappers, not profile boundaries.

## Related pages
- [[hermes-agent]]
- [[hermes-stack]]
- [[profile-separation]]
- [[provisioning-flow]]
