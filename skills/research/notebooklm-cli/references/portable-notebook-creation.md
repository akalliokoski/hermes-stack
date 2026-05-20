# Portable NotebookLM notebook creation workflow

Validated repo-first workflow for this user when creating NotebookLM notebooks from a Mac or other machine with a local ai-lab checkout.

## Goal

Create project notebooks without requiring extra environment variables or VPS-specific absolute paths.

## Standard scripts in `ai-lab`

- `scripts/create_notebooklm_notebook.sh`
- `scripts/create_openjaw_kickoff_notebook.sh`

## Design rules

- No required environment variables.
- Detect `nlm` from `PATH` with `command -v nlm`.
- Detect repo root from the script location, not from a hardcoded `/home/hermes/...` path.
- Accept a source-list manifest containing repo-relative paths.
- Ignore blank lines and `#` comments in the source list.
- Fail early if `nlm` is missing or `nlm login --check` fails.

## Default usage on macOS

From the local `ai-lab` checkout:

```bash
bash scripts/create_openjaw_kickoff_notebook.sh
```

Custom title:

```bash
bash scripts/create_openjaw_kickoff_notebook.sh "OpenJaw kickoff notebook - 2026-05-07"
```

Non-default NotebookLM CLI profile:

```bash
bash scripts/create_openjaw_kickoff_notebook.sh "OpenJaw kickoff notebook - 2026-05-07" --profile work
```

Generic reusable form:

```bash
bash scripts/create_notebooklm_notebook.sh path/to/source-list.txt "Notebook title"
```

## Pitfall

Do not hand the user a NotebookLM creation script with hardcoded VPS paths like `/home/hermes/.local/bin/nlm` or `/home/hermes/work/ai-lab` when they intend to run it on macOS. That breaks the user's default workflow. Prefer repo-relative, PATH-based scripts unless the user explicitly asks for a VPS-only helper.
