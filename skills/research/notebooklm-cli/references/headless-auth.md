# Headless NotebookLM auth on the Hermes VPS

Validated findings from the April 2026 setup session.

## What worked / did not work

- `uv tool install notebooklm-mcp-cli` installs both `nlm` and `notebooklm-mcp` for the `hermes` user.
- CLI-first is preferred over MCP here because the MCP server exposes about 35 tools, which would add prompt/tool-schema overhead to every Hermes session.
- `nlm login` initially failed with `No supported browser found` until a user-space Chromium was installed.
- A Playwright-installed Chromium could be launched headlessly with `--no-sandbox`, but that still did not solve first-time auth because NotebookLM login needs an interactive Google browser session.
- For this VPS, the reliable default is manual cookie import.

## Manual-cookie flow

1. On a laptop or workstation already logged into NotebookLM, open `https://notebooklm.google.com`.
2. Open DevTools.
3. Go to the Network tab.
4. Filter for `batchexecute`.
5. Trigger NotebookLM activity so a request appears.
6. Open one `batchexecute` request.
7. In Request Headers, copy the cookie header value only. Do not include the leading `cookie:` label.
8. Save that value on the VPS, e.g. `/home/hermes/.nlm/cookies.txt`.
9. Preferred import on the VPS with the repo helper:
   `pbpaste | ssh hermes@<vps> '/home/hermes/work/ai-lab/scripts/notebooklm_import_cookie.sh'`
10. Or, if the cookie was already saved on the VPS:
   `nlm login --manual --file /home/hermes/.nlm/cookies.txt`
11. Verify:
   `nlm login --check`

## Notes about scope

- NotebookLM auth is stored under `~/.notebooklm-mcp-cli/` for the Unix user, not per Hermes profile.
- Because Hermes profiles on this VPS all run as the same `hermes` user, one successful login is usable from all Hermes profiles.
- If multiple Google accounts are needed, use `nlm login --profile <name>` and `nlm login switch <name>`.

## Browser troubleshooting notes

- Browser automation may fail in hardened/container-like Linux environments unless Chromium is launched with `--no-sandbox`.
- Even with a working headless browser and CDP, first-time NotebookLM auth still depends on an interactive Google login path.
- If a real remote browser/CDP endpoint is available later, that can be revisited, but manual cookie import is the shortest reliable path for this VPS.
