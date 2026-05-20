# macOS -> Tailscale root SSH -> hermes NotebookLM cookie import

Validated pattern from May 2026.

## Why this pattern exists

- NotebookLM CLI auth is stored for the Unix user under `~/.notebooklm-mcp-cli/`.
- On this VPS, Hermes runs as the `hermes` Unix user.
- The user often connects over Tailscale SSH as `root` using an SSH profile.
- Therefore the correct transport/execution split is:
  1. capture the Cookie header on macOS
  2. SSH to the VPS as `root`
  3. switch to `hermes`
  4. run the import script as `hermes`

Do not run `nlm login --manual` as `root`, or the auth lands under `/root` and Hermes sessions running as `hermes` will not see it.

## Validated helper behavior

Preferred remote execution form:

```bash
su - hermes -c '/home/hermes/work/ai-lab/scripts/notebooklm_import_cookie.sh'
```

With a NotebookLM profile:

```bash
su - hermes -c '/home/hermes/work/ai-lab/scripts/notebooklm_import_cookie.sh --profile work'
```

## macOS wrapper pitfall

When writing Bash wrappers for macOS with `set -u`, do not forward an optional empty array like:

```bash
"${PROFILE_ARGS[@]}"
```

This can raise:

```text
unbound variable
```

Use a scalar variable such as `PROFILE_NAME` and branch explicitly:

```bash
if [[ -n "$PROFILE_NAME" ]]; then
  remote_cmd="... --profile $PROFILE_NAME"
else
  remote_cmd="..."
fi
```

## NotebookLM profile-name pitfall

Hermes profile names and NotebookLM CLI profile names are unrelated.

A Hermes session running under the `ai-lab` Hermes profile does not imply that `nlm login --check --profile ai-lab` will work. That flag only succeeds if a NotebookLM CLI profile named `ai-lab` was explicitly created with `nlm login --profile ai-lab`.

For troubleshooting, first test the default CLI profile with:

```bash
nlm login --check
```

Only add `--profile <name>` if `nlm profile list` shows that NotebookLM CLI profile actually exists.

## Repo helper scripts

Repo-local scripts created for this workflow:

- `/home/hermes/work/ai-lab/scripts/notebooklm_import_cookie.sh`
- `/home/hermes/work/ai-lab/scripts/notebooklm_push_cookie_from_macos.sh`

The macOS helper defaults to SSHing as `root` and then switching to `hermes` on the VPS.
