# Syncthing auth-bundle layout notes

Validated in the ai-lab VPS/macOS setup.

## macOS `nlm login` storage layout

Recent `nlm` builds may report:

- `Credentials saved to: ~/.notebooklm-mcp-cli/profiles/default`

That means:
- `cookies.json` is under `~/.notebooklm-mcp-cli/profiles/<profile>/cookies.json`
- `metadata.json` is under `~/.notebooklm-mcp-cli/profiles/<profile>/metadata.json`
- `auth.json` may be either:
  - `~/.notebooklm-mcp-cli/auth.json`, or
  - `~/.notebooklm-mcp-cli/profiles/<profile>/auth.json`, or
  - absent, in which case the ai-lab export helper can synthesize it from cookies + metadata

Do not assume `auth.json` is always root-level when guiding macOS export.

## Export/import helper behavior

`/home/hermes/work/ai-lab/scripts/notebooklm_export_auth_bundle.sh`
- reads `cookies.json` + `metadata.json` from the profile directory
- prefers root-level `auth.json`
- falls back to profile-local `auth.json`
- synthesizes `auth.json` if neither exists

`/home/hermes/work/ai-lab/scripts/notebooklm_import_auth_bundle.sh`
- imports bundle files into the target machine's `~/.notebooklm-mcp-cli`
- writes:
  - `auth.json`
  - `profiles/<profile>/cookies.json`
  - `profiles/<profile>/metadata.json`
- runs `nlm login --check` unless `--skip-check` is set

## VPS Syncthing path pitfall

In this setup, Syncthing on the VPS runs inside Docker.

So the Syncthing web UI must use container-visible paths, not raw host paths.

Examples:
- host `/home/hermes/sync` -> container `/sync`
- host `/home/hermes/codeo-sync` -> container `/codeo-sync` (after the hermes-stack mount change is deployed)

If the operator enters `/home/hermes/...` in the Syncthing UI, Syncthing may fail with errors like:
- `mkdir /home/hermes: permission denied`
- `Failed initial scan (error="folder path missing")`

Correct fix:
- use `/sync/...` for the main shared root
- use `/codeo-sync/...` for the dedicated separate Mac `codeo` parent root after deployment

## Dedicated mount ownership pitfall

A live Docker bind mount alone is not enough; the underlying host path must also be writable by the Syncthing process inside the container.

Validated case on this VPS:
- host `/home/hermes/codeo-sync` existed
- container `/codeo-sync` existed
- but the host directory initially came up as `root:root`
- Syncthing itself ran as uid/gid `999:987`

Symptom:
- folder path exists, but Syncthing still cannot create files/subfolders there

Correct check/fix sequence:
1. confirm the mount is live with `docker inspect` or `docker exec ... ls -ld /codeo-sync`
2. confirm the host owner/mode with `ls -ld /home/hermes/codeo-sync`
3. confirm the Syncthing runtime uid/gid inside the container
4. adjust ownership on the mounted host path to match the effective Syncthing uid/gid
5. verify by creating a file as that uid/gid before retrying folder acceptance
