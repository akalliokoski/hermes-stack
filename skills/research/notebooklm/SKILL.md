---
name: notebooklm
description: Use when the user wants Google NotebookLM access from Hermes. This shared skill makes other profiles aware that NotebookLM is available on this VPS and that the CLI-first path is the default.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [notebooklm, research, cli, shared, cross-profile]
    related_skills: [notebooklm-cli]
---

# NotebookLM

## Overview

NotebookLM is available to Hermes profiles on this VPS through a shared install for the `hermes` Unix user.

This is a lightweight awareness skill: it tells profiles that NotebookLM capability exists and points them to the more detailed `notebooklm-cli` skill for actual workflows.

## What is available

- `nlm` CLI is installed for the shared `hermes` user.
- `notebooklm-mcp` is also installed, but it is not enabled globally by default.
- Authentication is shared at the Unix-user level, not per Hermes profile.
- Because profiles on this VPS run as the same `hermes` user, one valid NotebookLM login can be reused across profiles.

## Default approach

Prefer the CLI-first path.

Why:
- It is more token-efficient than exposing the full NotebookLM MCP tool surface in every session.
- Profiles only pay context/tool overhead when they actually use NotebookLM.
- It fits the VPS setup better, especially when NotebookLM is only used occasionally.

## Typical use cases

Use NotebookLM when the user wants to:
- create a research notebook
- ingest URLs, docs, or raw text
- query a notebook for summaries or synthesis
- generate short audio deep-dives or other study artifacts

## How to use it from Hermes

If a task needs NotebookLM, load the detailed skill:

- `notebooklm-cli`

Then use terminal commands such as:

```bash
nlm login --check
nlm notebook list --json
nlm notebook create "Topic"
nlm source add --text "..." --title "Notes" --wait
nlm notebook query "Summarize the main ideas"
```

## Operational note

If NotebookLM stops working, the most likely issue is expired browser-cookie auth. Re-check with:

```bash
nlm login --check
```

If auth needs repair, use the documented flow in the `notebooklm-cli` skill.

## Verification Checklist

- [ ] `nlm` exists on PATH for the `hermes` user
- [ ] `nlm login --check` succeeds when NotebookLM auth is still valid
- [ ] the `notebooklm-cli` skill is available for detailed workflows
