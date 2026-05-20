# macOS + Syncthing auth-bundle setup

Use this when the user wants the easiest practical NotebookLM auth flow between a browser-capable Mac and a headless VPS.

## Goal
- authenticate with `nlm login` on macOS
- export only the NotebookLM auth bundle
- sync it to the VPS with Syncthing
- import it into the VPS Unix user's `nlm` auth store
- verify with `nlm login --check`

## macOS install bootstrap
Install `uv` with Homebrew:

```bash
brew install uv
```

Install the CLI:

```bash
uv tool install notebooklm-mcp-cli
```

If `nlm` is not on `PATH`, add uv's default tool bin directory:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

Verify:

```bash
nlm --version
nlm login
nlm login --check
```

## Preferred ai-lab bundle handoff
On the Mac, export into the shared Syncthing folder:

```bash
/path/to/ai-lab/scripts/notebooklm_export_auth_bundle.sh --dest-dir ~/Syncthing/notebooklm-auth
```

This exports exactly:
- `auth.json`
- `cookies.json`
- `metadata.json`

For a non-default NotebookLM CLI profile:

```bash
/path/to/ai-lab/scripts/notebooklm_export_auth_bundle.sh --profile work --dest-dir ~/Syncthing/notebooklm-auth
```

## VPS import
After Syncthing delivers the files, import as the target Unix user that actually runs `nlm`:

```bash
/home/hermes/work/ai-lab/scripts/notebooklm_import_auth_bundle.sh
/home/hermes/.local/bin/nlm login --check
```

For a non-default profile:

```bash
/home/hermes/work/ai-lab/scripts/notebooklm_import_auth_bundle.sh --profile work
```

## Syncthing notes
- Prefer syncing only the small auth-bundle folder, not the whole browser profile.
- Recommended Mac root: `~/Syncthing`
- Recommended bundle folder: `~/Syncthing/notebooklm-auth`
- Recommended VPS destination in this setup: `/home/hermes/sync/notebooklm-auth`

## Pitfalls
- Do not import NotebookLM auth as `root` if the real CLI runs as another user; the auth store is Unix-user scoped.
- If a fresh synced bundle still fails `nlm login --check`, stop retrying raw cookie-header copies and fall back to the external CDP flow.
- NotebookLM CLI profile names are separate from Hermes profile names; only use `--profile NAME` if that NotebookLM CLI profile actually exists.
