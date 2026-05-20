---
name: wiki-todo-overview
description: Summarize or inspect todo notes across multiple Hermes profiles in the shared wiki vault.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [todo, wiki, obsidian, profile, workflow, summary]
    related_skills: [wiki-todo, obsidian, llm-wiki]
    config:
      - key: wiki.path
        description: Path to the shared wiki / Obsidian vault used for per-profile todo notes.
        default: ~/sync/wiki
        prompt: Shared wiki path
---

# Wiki Todo Overview

Use this skill when the user asks for a cross-profile todo summary, wants to compare profile task lists, or asks things like:

- `show all profile todos`
- `which profiles have open tasks?`
- `summarize my todos across profiles`
- `find the profile with task X`

## Goal

Keep one shared vault, but read across the profile-scoped todo files created by `wiki-todo`.

Expected layout:

- `profiles/default/todos.md`
- `profiles/<profile>/todos.md`

## Resolve the wiki path

Use the same fallback chain as `wiki-todo`:

```bash
WIKI="${WIKI_PATH:-${OBSIDIAN_VAULT_PATH:-$HOME/sync/wiki}}"
```

## Discover todo files

Search under the wiki for:

```bash
profiles/*/todos.md
```

Do not assume every profile has a file yet.

## What to report

For each file, extract:
- profile name
- count of open todos (`- [ ]`)
- count of done todos (`- [x]`)
- optionally the titles of open tasks

Default output should be concise, for example:

```markdown
- default — 2 open, 4 done
- gemma — 1 open, 0 done
```

If the user asks for detail, include the open items under each profile.

## Search mode

If the user asks to find a specific task or phrase:
1. Search all `profiles/*/todos.md` files for the phrase or todo ID.
2. Return matching profile(s), IDs, and task text.

## Recommended tools

- `search_files` → find `profiles/*/todos.md` and search for IDs/text
- `read_file` → inspect individual todo files
- `terminal` → date if you need to mention freshness or generate normalized reports

## Pitfalls

- Do not merge tasks from different profiles into one note.
- Distinguish between summary mode and edit mode: this skill reads/summarizes; `wiki-todo` edits.
- If a profile file is missing, treat that as `0 open, 0 done`, not as an error, unless the user asked specifically about that profile.
