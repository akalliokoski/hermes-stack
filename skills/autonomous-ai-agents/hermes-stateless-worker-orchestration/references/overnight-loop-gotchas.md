# Overnight loop gotchas

Captured from an OpenJaw overnight orchestration debugging pass on 2026-05-14.

## Failure mode 1: missing named session loop

Symptom:
- repeated log entries like:
  - `No session found matching 'openjaw-yasar-night1'.`
  - `Use 'hermes sessions list' to see available sessions.`

Cause:
- the loop called `hermes chat --continue <session-name>` before such a session existed.

Fix:
- for bounded overnight loops, prefer stateless `hermes chat -q ...` passes that read/write a handoff file.
- only use `--continue` after verifying the session already exists and continuity is actually required.

## Failure mode 2: bad HERMES_HOME from inherited HOME

Symptom:
- error like:
  - `Missing Hermes home for profile 'ai-lab': /home/hermes/.hermes/profiles/ai-lab/home/.hermes/profiles/ai-lab`

Cause:
- the script assumed `$HOME/.hermes` was the account-level Hermes home.
- in background/profile-launched contexts, `$HOME` can already point inside a profile-local location.

Fix:
- derive the account home from the passwd database, e.g. `getent passwd "$(id -un)" | cut -d: -f6`, then build `~/.hermes` from that resolved home.

## Failure mode 3: false early stop from sentinel phrase

Symptom:
- the loop exits immediately with:
  - `Stopping because handoff requested: recommended next mode: stop`
- but the handoff only contains instructional text like "If verification fails ... write `recommended next mode: stop`."

Cause:
- the stop detector matched the phrase anywhere in the file rather than only a dedicated sentinel line.

Fix:
- anchor the regex to a whole line such as:
  - `^\s*recommended\s+next\s+mode\s*:\s*(\w+)\s*$`

## Verification checklist after a fix

1. Confirm the parent loop process is alive.
2. Confirm a child `hermes chat` process is actually running.
3. Confirm the log file gets a fresh pass entry after the fix.
4. Confirm either the handoff timestamp changes or the pass writes concrete output.
5. If the loop claims success but artifacts are unchanged, inspect the exact child command and stdout/stderr before trusting it.
