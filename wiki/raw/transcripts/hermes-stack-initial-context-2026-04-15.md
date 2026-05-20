# Hermes Stack Initial Context

Captured: 2026-04-15
Type: local context snapshot
Purpose: seed the wiki with immutable source material gathered during vault initialization

## Provenance
- `/home/hermes/work/hermes-stack/SETUP.md`
- `/home/hermes/work/hermes-stack/scripts/provision-profile.sh`
- `/home/hermes/work/hermes-stack/AGENTS.md`
- `/home/hermes/.hermes/shared/soul/README.md`
- `/home/hermes/.hermes/config.yaml`

## Extracted facts
- `hermes-agent` runs natively on the VPS under systemd as user `hermes`, while Docker Compose runs auxiliary services such as Firecrawl, Hindsight, Litestream, backup, and Syncthing.
- The canonical deployment repo is `/home/hermes/work/hermes-stack`.
- The default profile terminal workspace is mounted from `/home/hermes/work/default` to `/workspace`.
- Shared instructions live under `~/.hermes/shared/soul/base.md` plus `~/.hermes/shared/soul/profiles/<name>.md`.
- Profile provisioning renders each profile `SOUL.md` from the shared base plus the matching profile override file.
- Hindsight isolation is implemented with one shared service URL and a per-profile `bankId` such as `hermes-default` or `hermes-<profile>`.
- The provisioning flow creates a profile-specific workspace under `/home/hermes/work/<profile>` and rewrites Docker terminal mounts accordingly.
- The default-profile override file currently exists at `~/.hermes/shared/soul/profiles/default.md` and was empty at initialization time.
- The synced wiki path in config is `/home/hermes/sync/wiki`.

## Notes
These facts were captured to ground initial wiki pages. Future updates should add new raw source files instead of editing this one.
