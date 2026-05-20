# macOS Chrome CDP tunnel auth for headless VPS NotebookLM

Validated fallback when manual Cookie-header import lands in the correct auth store but `nlm login --check` still reports `Authentication expired`.

## When to use this path

Use this when:
- the VPS is headless
- the user has a working logged-in NotebookLM session in a browser on macOS
- manual Cookie-header copy/import appears correct but still fails validation

Why it helps:
- `nlm login --cdp-url ...` can read live browser state directly instead of relying on a copied raw Cookie header
- this external-CDP path extracts not only cookies but also page-derived metadata used by the CLI auth flow:
  - CSRF token
  - session ID
  - build label

## Recommended flow

1. On the Mac, fully quit Chrome first so the debugging flag is applied to a fresh process.

```bash
osascript -e 'tell application "Google Chrome" to quit'
```

2. Relaunch Chrome with local remote debugging enabled.

```bash
open -a "Google Chrome" --args --remote-debugging-port=9222
```

3. In that Chrome window, open `https://notebooklm.google.com` and ensure the session is live.

4. From the Mac, open an SSH reverse tunnel to the VPS and keep it running.

```bash
ssh -N -R 18800:127.0.0.1:9222 root@vps
```

5. On the VPS, run `nlm login` as the `hermes` Unix user against the tunneled CDP endpoint.

```bash
sudo -iu hermes /home/hermes/.local/bin/nlm login --cdp-url http://127.0.0.1:18800
```

6. Verify immediately.

```bash
sudo -iu hermes /home/hermes/.local/bin/nlm login --check
```

## One-shot variant

If the user prefers a single SSH command from the Mac:

```bash
ssh -tt -R 18800:127.0.0.1:9222 root@vps "sudo -iu hermes /home/hermes/.local/bin/nlm login --cdp-url http://127.0.0.1:18800"
```

Keep the Mac browser open on NotebookLM while this runs.

## Important cautions

- Run the login as `hermes`, not `root`, so auth lands under `/home/hermes`.
- Keep the browser debugging port bound only to localhost on the Mac; use SSH tunneling rather than exposing the port on the network.
- If Chrome is already running, it may ignore the new debug flag. A full quit/relaunch is safer than opening a new window.
- If needed, a stricter restart sequence on macOS is:

```bash
osascript -e 'tell application "Google Chrome" to quit'
pkill -f "Google Chrome" || true
open -a "Google Chrome" --args --remote-debugging-port=9222
```

## Why this belongs in the skill

The upstream CLI explicitly supports external CDP auth via `--cdp-url`. For this VPS + macOS operator setup, that can be a more reliable fallback than manual Cookie-header transport when copied cookies validate poorly even though the import path itself is correct.
