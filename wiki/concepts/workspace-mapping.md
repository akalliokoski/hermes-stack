---
title: Workspace Mapping
created: 2026-04-15
updated: 2026-04-15
type: concept
tags: [workspace, profile, config, workflow, docker, default-profile]
sources: [raw/articles/hermes-stack-setup-operations-2026-04-15.md, raw/articles/hermes-stack-provision-profile-script-2026-04-15.md]
---

# Workspace Mapping

## Definition
Workspace mapping is the rule that every Hermes profile gets its own host directory under `/home/hermes/work/<profile>` which is bind-mounted into the Docker shell sandbox as `/workspace`.

## Current behavior
- the default profile uses `/home/hermes/work/default:/workspace`
- named profiles get `/home/hermes/work/<name>:/workspace`
- the provisioning script rewrites profile config from the default mount to the profile-specific mount
- sandboxed shell commands see only that profile directory as writable workspace

## Why it matters
This is the filesystem half of [[profile-separation]]. It prevents routine shell work from crossing profile boundaries accidentally while preserving a simple mental model for the agent: always work in `/workspace`.

## Default-profile implication
Because the default profile maps to `/home/hermes/work/default`, any repo treated as current priority for the default profile should generally live there or be copied there when strict sandbox visibility matters. In practice, `[[hermes-stack]]` is the current operational priority.

## Related pages
- [[profile-separation]]
- [[provisioning-flow]]
- [[hermes-stack]]
- [[hermes-agent]]
