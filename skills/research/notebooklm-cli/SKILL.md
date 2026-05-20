---
name: notebooklm-cli
description: Use the shared NotebookLM CLI on the VPS for notebook creation, source ingestion, querying, and audio/video/study artifact generation without adding a large MCP tool surface to every Hermes session.
---

# NotebookLM CLI

Use this skill when the user wants Hermes to work with Google NotebookLM from any Hermes profile on this machine.

This is a shared cross-profile skill. It lives in `/home/hermes/.hermes/shared/skills`, so profiles that include the shared skills directory can load it.

## Why CLI-first is the default here

Prefer the CLI (`nlm`) over the MCP server for general Hermes use on this VPS.

Reason:
- The upstream package exposes both a CLI and an MCP server in one install.
- The MCP server exposes about 35 tools.
- In Hermes, MCP tools are discovered at startup and injected into the tool registry for every session.
- That means more tool schema text in context on every turn, even when NotebookLM is not being used.
- Using the CLI through Hermes terminal calls avoids that permanent schema overhead and is therefore more token-efficient.

Use MCP only if you specifically want first-class structured NotebookLM tools available in every session and are willing to pay the extra prompt/tool-schema cost.

## Installed binaries

The package is installed once for the `hermes` user:

- `nlm`
- `notebooklm-mcp`

Expected locations:
- `/home/hermes/.local/bin/nlm`
- `/home/hermes/.local/bin/notebooklm-mcp`

## Authentication model

NotebookLM has no official public API here; this tool uses browser cookies.

Primary auth command:

```bash
nlm login
```

Useful variants:

```bash
nlm login --check
nlm login --profile work
nlm login switch work
nlm login profile list
```

Important notes:
- Treat NotebookLM CLI auth as Unix-user scoped and CLI-profile scoped, not Hermes-profile scoped.
- Do not assume a specific on-disk auth path from memory; older notes may mention `~/.notebooklm-mcp-cli/`, while repo helpers also use `/home/hermes/.nlm/` for cookie handoff. The reliable check is always `nlm login --check` in the same execution context that will run the real command.
- Hermes profile names and NotebookLM CLI profile names are different namespaces. `--profile ai-lab` only works if an actual NotebookLM CLI profile named `ai-lab` was created with `nlm login --profile ai-lab`; do not assume Hermes profiles automatically exist inside `nlm`.
- Before any long ingestion/upload job, run `nlm login --check` first. If it fails, refresh auth before starting the job.
- On a headless VPS, browser-based login may need either forwarded GUI access, a remote browser/CDP endpoint, or manual cookie import.
- In this environment, the practical default is manual cookie import from another machine that already has an authenticated NotebookLM browser session.
- For this user, the smooth default is: capture the Cookie header from NotebookLM DevTools on macOS, SSH to the VPS as `root` over Tailscale, then switch to the `hermes` Unix user with `su - hermes -c ...` before running the import script. Do not import as `root`, because NotebookLM auth needs to land under the `hermes` user's auth store.
- On this VPS, if the operator logs in as `root` over Tailscale/SSH, switch to the `hermes` Unix user before importing cookies; do not import NotebookLM auth as `root` or the resulting session state will land under the wrong user.
- In the ai-lab workspace, the current preferred helper flow is a Syncthing auth-bundle handoff rather than raw Cookie import. Export from the logged-in machine with `/home/hermes/work/ai-lab/scripts/notebooklm_export_auth_bundle.sh`, sync the resulting `auth.json`, `cookies.json`, and `metadata.json`, then import on the VPS with `/home/hermes/work/ai-lab/scripts/notebooklm_import_auth_bundle.sh`.
- The export helper is intentionally tolerant of recent CLI storage-layout differences: it always reads `cookies.json` and `metadata.json` from `~/.notebooklm-mcp-cli/profiles/<profile>/`, prefers root-level `~/.notebooklm-mcp-cli/auth.json` when present, falls back to profile-local `auth.json` if present, and can synthesize `auth.json` from the other two files when needed.
- The default VPS-side bundle drop folder in `ai-lab` remains `/home/hermes/sync/notebooklm-auth`, with a README describing the expected files.
- On macOS with recent `nlm` versions, a successful `nlm login` may report `Credentials saved to: ~/.notebooklm-mcp-cli/profiles/<profile>`. Treat that as normal: `cookies.json` and `metadata.json` are profile-local, while `auth.json` may live either at `~/.notebooklm-mcp-cli/auth.json` or alongside the profile files depending on version/layout.
- The ai-lab export helper was updated to handle that layout drift: it reads `cookies.json` and `metadata.json` from `~/.notebooklm-mcp-cli/profiles/<profile>/`, prefers root-level `auth.json` when present, falls back to profile-local `auth.json`, and can synthesize `auth.json` from the other two files if needed.
- If the user wants a separate Syncthing parent for a Mac user (for example `codeo/notebooklm-auth`) instead of placing the bundle under the existing `/sync` tree, remember that the VPS Syncthing service here runs inside Docker. The Syncthing UI must use container-visible paths, not host paths. After the dedicated mount is deployed in `hermes-stack`, the correct separate parent path is `/codeo-sync` in the Syncthing UI, which maps to host `/home/hermes/codeo-sync`.
- After adding a new dedicated Syncthing bind mount on this VPS, verify both path mapping and ownership before telling the user to accept the folder. In the validated `codeo-sync` case, the mount existed live but the host directory initially came up owned by `root:root`, while Syncthing actually ran as uid/gid `999:987`. The fix was to adjust ownership on the mounted path so the Syncthing process could write there, then re-test by writing as uid/gid `999:987`.
- If syncing a fresh auth bundle still fails `nlm login --check`, then fall back to external CDP auth from the Mac browser instead of retrying raw Cookie copy indefinitely.
- For this user's setup, the best fallback after bundle-sync failure is: launch Chrome on macOS with `--remote-debugging-port=9222`, tunnel it to the VPS with `ssh -R 18800:127.0.0.1:9222 root@vps`, then run `sudo -iu hermes /home/hermes/.local/bin/nlm login --cdp-url http://127.0.0.1:18800` on the VPS.
- If the operator says auth was refreshed, verify immediately with `nlm login --check` before attempting notebook creation or bulk source uploads.
- See `references/syncthing-auth-bundle-layout.md` for the validated macOS profile-path variation, export-helper fallback behavior, and the Dockerized VPS Syncthing path-mapping pitfall (`/sync` vs `/home/hermes/...`, `/codeo-sync` for the separate codeo parent root).
- See `references/headless-auth.md` for the validated VPS-specific auth troubleshooting path.
- See `references/ai-lab-helper-scripts.md` for the helper-script workflow and the macOS `set -u` optional-array pitfall.
- Project-specific NotebookLM helper scripts in the repo may be VPS-bound rather than portable. Before telling the user to run an existing `.sh` file from macOS, inspect it for hardcoded Linux/VPS paths such as `/home/hermes/.local/bin/nlm`, `/home/hermes/work/ai-lab`, fixed source manifests, or assumptions about the `hermes` Unix user. If those are present, do not say they can "just run it" on the Mac unchanged; explain the required path/`nlm` adjustments first. A validated example is `/home/hermes/work/ai-lab/scripts/create_openjaw_kickoff_notebook.sh`, which creates the OpenJaw kickoff notebook but hardcodes VPS paths for `NLM_BIN`, `SOURCE_LIST`, and `REPO_ROOT`.
- See `references/macos-cookie-helper.md` for the older root-SSH -> `su - hermes` raw-cookie import pattern and the NotebookLM-vs-Hermes profile-name pitfall.
- See `references/macos-syncthing-auth-bundle-setup.md` for the current easiest macOS-first setup: install `nlm` on the Mac with `uv`, log in locally, export `auth.json`/`cookies.json`/`metadata.json`, sync them via Syncthing, then import on the VPS.
- See `references/portable-notebook-creation.md` for the preferred repo-first macOS workflow for creating notebooks with no extra environment variables, using PATH-based `nlm` discovery and repo-relative source manifests.
- See `references/current-state-handoff-notebooks.md` for validation/research notebook packages that need an explicit "what has actually been done vs not done" source, repo-relative source manifest, Mac-portable wrapper, and source/path verification before upload.
- See `references/macos-cdp-tunnel-auth.md` for the external-CDP fallback using a live Mac browser tunneled into the VPS.
- See `references/artifact-download-auth.md` for validated artifact-download failure modes where notebook access works but final audio or slide-deck downloads still fail on the binary fetch step.


## Best-use pattern from Hermes

When operating from Hermes, prefer terminal commands like:

```bash
nlm notebook list --json
nlm notebook create "Topic title"
nlm source add --url "https://example.com" --wait
nlm notebook query "Summarize the main ideas"
nlm audio create --confirm
nlm download audio
```

If you need machine-readable output for Hermes reasoning, prefer JSON flags when available:

```bash
nlm notebook list --json
```

## Common workflows

### Create a notebook from a repo source-list manifest

When the user wants a durable default workflow, prefer a repo-first helper script that:
- discovers `nlm` from `PATH`
- discovers the repo root from the script location
- reads a manifest of repo-relative source paths
- requires no extra environment variables

In `ai-lab`, the validated examples are:
- `scripts/create_notebooklm_notebook.sh`
- `scripts/create_openjaw_kickoff_notebook.sh`
- `scripts/create_openjaw_bruxsynth_validation_notebook.sh`

If the target machine is the user's Mac, prefer this style over VPS-specific absolute paths.

For validation/research notebooks, put a concise current-state handoff document first in the source manifest. It should explicitly distinguish actual completed runs/artifacts from planned work, pending validation, and compute limitations so NotebookLM does not blur aspiration into evidence; see `references/current-state-handoff-notebooks.md`.

### Create a notebook and add a URL

```bash
nlm notebook create "Research Project"
nlm source add --url "https://example.com" --wait
```

### Add raw text

```bash
nlm source add --text "...content..." --title "Notes" --wait
```

### Query a notebook

```bash
nlm notebook query "What are the key findings?"
```

### Generate podcast/audio

```bash
nlm audio create --confirm
nlm studio status <notebook-id>
nlm download audio <notebook-id> --output /path/to/output.m4a
```

Verification rule:
- Do not treat audio creation as complete until the file download succeeds locally.
- Apply the same rule to slide decks and other binary artifacts: `completed` in `nlm studio status` is not enough by itself.
- `nlm login --check` can pass while `nlm download audio` still fails due to the final media URL redirecting to Google login.
- Slide-deck download can also fail after successful generation, including a `403 Forbidden` from Google artifact hosting.
- If that happens, refresh the manual cookie export and retry; see `references/artifact-download-auth.md`.

### Generate video or study materials

```bash
nlm video create --confirm
nlm studio create quiz --confirm
nlm studio create flashcards --confirm
```

## Operational cautions

- Upstream uses undocumented internal APIs and may break without notice.
- Browser cookies expire; if commands start failing unexpectedly, rerun `nlm login` or `nlm login --check`.
- `nlm login --check` only proves notebook-session access. Artifact downloads may still fail if the media URL cookie scope is stale or incomplete.
- When download failure persists after a fresh cookie import, preserve the notebook URL and artifact IDs for handoff, and tell the user to retrieve the completed artifact from the NotebookLM web UI rather than claiming the job failed.
- For long source-ingestion flows, use `--wait` so follow-up commands do not race processing.
- For destructive commands, require explicit confirmation flags where the CLI expects them.

## When to choose MCP instead

Choose the MCP server only when all of these are true:
1. You want NotebookLM operations exposed as native tools rather than terminal commands.
2. You expect frequent NotebookLM use in that profile.
3. You accept extra prompt/tool-schema overhead from ~35 additional tools.

If that becomes necessary later, configure Hermes `mcp_servers` with the `notebooklm-mcp` binary in the specific profiles that need it instead of enabling it globally everywhere.
