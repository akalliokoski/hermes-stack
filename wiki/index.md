# Wiki Index

> Content catalog for Hermes operations knowledge.
> Read this first to find relevant pages and current priorities.
> Last updated: 2026-05-08 | Total pages: 10

## Entities
- [[hermes-agent]] — The core Hermes runtime whose profile model and memory capabilities are operationalized by the stack.
- [[hermes-stack]] — The deployment repo and operational control plane currently prioritized by the default profile.
- [[hindsight-memory]] — Shared Hindsight service with per-profile logical banks for memory isolation.
- [[syncthing]] — File sync layer for mirroring the `.hermes` tree, including the wiki vault, across devices.

## Concepts
- [[profile-separation]] — How profiles are separated by workspace, config, and memory while still sharing selected instruction sources.
- [[provisioning-flow]] — The canonical create-or-update path for Hermes profiles and SOUL rendering in the stack.
- [[shared-soul]] — The shared SOUL layout that composes common instructions with per-profile overrides.
- [[workspace-mapping]] — How each profile gets its own writable `/workspace` via profile-specific host mounts.

## Comparisons

## Queries
- [[default-hermes-stack-autoresearch-loop-setup-2026-05-04]] — Notes how the default-profile autoresearch loop should use the shared wiki and why the loop is currently paused for stability.
- [[default-hermes-multiprofile-simplification-audit-2026-05-08]] — Audit of how much hermes-stack can now lean on upstream Hermes multi-profile and per-profile gateway support.
