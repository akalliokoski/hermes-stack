---
title: Default Hermes Stack Autoresearch Loop Setup 2026-05-04
created: 2026-05-04
updated: 2026-05-04
type: query
tags: [automation, workflow, default-profile, documentation]
sources: [/home/hermes/work/default/autoresearch/default-hermes-stack-loop-prompt.md, /home/hermes/.hermes/cron/jobs.json]
---

# Default Hermes Stack Autoresearch Loop Setup 2026-05-04

## Current state

The default profile has a bounded autoresearch loop for `/home/hermes/work/hermes-stack`, but it is intentionally paused for stability.

## Bookkeeping rule

If the loop is resumed later, each pass should:
- inspect the shared wiki first (`SCHEMA.md`, `index.md`, recent `log.md`)
- keep default-profile notes inside the shared vault instead of creating a separate wiki root
- update the relevant shared-wiki page or add a query page when understanding materially changes
- append a chronological entry to the shared `log.md`

## Why paused

The user explicitly preferred not to keep the default-profile autoresearch loop enabled right now, so runtime stability takes priority over autonomous iteration for this profile.

## Related pages

- [[hermes-stack]]
- [[profile-separation]]
- [[shared-soul]]
