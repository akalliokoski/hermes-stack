---
name: wiki-todo
description: Manage simple per-profile todo notes inside the shared wiki/Obsidian vault.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [todo, wiki, obsidian, profile, workflow]
    related_skills: [obsidian, llm-wiki]
    config:
      - key: wiki.path
        description: Path to the shared wiki / Obsidian vault used for per-profile todo notes.
        default: ~/sync/wiki
        prompt: Shared wiki path
---

# Wiki Todo

Use this skill when the user asks to add, edit, list, complete, reopen, or otherwise manage todos in the shared wiki / Obsidian vault.

## Goal

Keep todos in one shared vault while separating them by Hermes profile.

Path convention:

- active profile `default` → `profiles/default/todos.md`
- profile `gemma` → `profiles/gemma/todos.md`
- generic rule → `profiles/<profile>/todos.md`

This keeps the vault shared across profiles, but keeps each profile's task list isolated.

## Resolve the wiki path

Prefer the configured wiki path. In practice, use this fallback chain:

```bash
WIKI="${WIKI_PATH:-${OBSIDIAN_VAULT_PATH:-$HOME/sync/wiki}}"
```

For this user's setup, `~/sync/wiki` is the intended shared vault unless they explicitly redirect you.

## Resolve the target profile

1. If the user explicitly names a profile, use that.
2. Otherwise detect the active profile:

```bash
hermes profile
```

Parse the `Active profile:` line. If detection fails, fall back to `default`.

## Todo file format

Each profile has one markdown file at `profiles/<profile>/todos.md`.

Use this structure:

```markdown
---
title: <profile> todos
profile: <profile>
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: summary
tags: [profile, workflow]
sources: []
---

# <profile> todos

## Open
- [ ] [<profile>-YYYYMMDD-001] Example task
  - created: YYYY-MM-DD
  - notes: optional details

## Done
```

Rules:
- Use lowercase profile names in the path and IDs.
- IDs must be stable. Format: `<profile>-YYYYMMDD-NNN`.
- New tasks go under `## Open`.
- Completed tasks move to `## Done` and switch to `- [x]`.
- When anything changes, bump the top-level `updated:` date.

## If the file does not exist

Create `profiles/<profile>/todos.md` from the template in `templates/profile-todos.md`, replacing:
- `__PROFILE__`
- `__DATE__`

Also ensure the parent directory exists.

## Common operations

### List todos

1. Resolve the profile and todo file path.
2. Read the file.
3. Report open items first, then done items if the user asked for completed tasks too.
4. Keep the response concise: ID + checkbox state + title.

### Add a todo

1. Resolve profile + file.
2. If needed, initialize the file.
3. Generate today's date with `date +%F` and derive the next sequence number for that date by scanning existing IDs in the file.
4. Insert a block under `## Open`:

```markdown
- [ ] [<id>] Task text
  - created: YYYY-MM-DD
  - notes: optional details
```

5. Update top-level `updated:`.
6. Confirm the new ID back to the user.

### Edit a todo

1. Find the todo block by ID.
2. Update the first-line task text and/or the `notes:` line.
3. Update top-level `updated:`.
4. Keep the same ID.

### Mark done

1. Find the full todo block under `## Open`.
2. Change `- [ ]` to `- [x]`.
3. Move the whole block to `## Done`.
4. Add a `  - completed: YYYY-MM-DD` line if it is not already present.
5. Update top-level `updated:`.

### Reopen a todo

1. Find the block under `## Done`.
2. Change `- [x]` back to `- [ ]`.
3. Remove the `completed:` line.
4. Move it back to `## Open`.
5. Update top-level `updated:`.

### Delete a todo

Delete the full block by ID, then update top-level `updated:`.
Only do this when the user explicitly asks to delete it; otherwise prefer marking done.

## Recommended tools

- `terminal` → `hermes profile`, `date +%F`
- `read_file` → inspect the current todo note
- `search_files` → locate existing todo files or IDs
- `write_file` → initialize the file from the template
- `patch` → edit existing task blocks safely

## Example workflow

User: `Add buy milk to my todos`

1. Detect active profile.
2. Resolve `WIKI/profiles/<profile>/todos.md`.
3. Initialize the file if missing.
4. Add a new unchecked item under `## Open`.
5. Return the assigned ID.

## Pitfalls

- Do not mix todos from different profiles in one file.
- Do not create separate wiki roots per profile; keep one shared vault with profile-scoped todo files.
- Do not change todo IDs after creation.
- When editing by text alone is ambiguous, search by ID first.
- When the user says `my todos`, default to the active profile's file.
