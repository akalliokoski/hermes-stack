# ai-lab NotebookLM helper scripts

Validated helper flow for this VPS + Mac setup.

## Goal

Capture a live NotebookLM `Cookie` request header on the Mac, then import it on the VPS for the `hermes` Unix user without needing a browser on the VPS.

## Important rule

Run NotebookLM auth import as `hermes`, not `root`.

Reason:
- NotebookLM auth state is stored under the Unix user's home.
- If you run `nlm login --manual ...` as `root`, the cookies land under `/root` and Hermes sessions running as `hermes` will not reuse them.

## Repo helper scripts

VPS-side import helper:
- `/home/hermes/work/ai-lab/scripts/notebooklm_import_cookie.sh`

Mac-side push helper:
- `/home/hermes/work/ai-lab/scripts/notebooklm_push_cookie_from_macos.sh`

## Default Mac flow

The Mac helper now defaults to:
- SSH target: `root@vps`
- remote user switch: `su - hermes -c ...`

So the intended default usage on the Mac is:

```bash
scripts/notebooklm_push_cookie_from_macos.sh
```

Optional profile-specific usage:

```bash
scripts/notebooklm_push_cookie_from_macos.sh --profile work
```

Optional overrides:

```bash
export NOTEBOOKLM_VPS_TARGET=root@vps
export NOTEBOOKLM_REMOTE_USER=hermes
export NOTEBOOKLM_REMOTE_SCRIPT=/home/hermes/work/ai-lab/scripts/notebooklm_import_cookie.sh
```

## Capture steps on the Mac

1. Open `https://notebooklm.google.com`
2. Open DevTools
3. Network tab
4. Filter for `batchexecute`
5. Open a request
6. Copy the `Cookie` request header value only
7. Run the Mac helper

## Shell pitfall found on macOS

For bash helpers running with `set -u`, avoid expanding an optional empty array like:

```bash
"${PROFILE_ARGS[@]}"
```

This triggered `unbound variable` on macOS bash when no `--profile` flag was passed.

Safer pattern for small helpers:
- store the optional profile in a scalar like `PROFILE_NAME`
- branch explicitly when assembling the final command
