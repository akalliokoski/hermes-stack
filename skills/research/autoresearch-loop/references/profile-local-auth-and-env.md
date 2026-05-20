# Profile-local auth/env pitfalls for cron loops

When a loop is moved from the global Hermes home into a profile-local `HERMES_HOME`, the scheduler may look healthy but actual jobs can still fail immediately if the profile lacks credentials or fallback env vars.

Observed failure pattern
- ticker runs normally
- job becomes due
- cron output file is created with a failure
- logs show one of:
  - `No Codex credentials stored. Run \`hermes auth\` to authenticate.`
  - fallback attempted
  - `OPENROUTER_API_KEY not set`
  - `RuntimeError: No LLM provider configured.`

Fast verification checklist
1. Check profile-local `auth.json` exists if the selected provider uses stored auth.
2. Check profile-local `.env` contains any fallback provider keys the runtime may resolve to.
3. Inspect profile-local logs, not only global logs.
4. Confirm session artifacts land under `<profile>/sessions/session_cron_*.json`.
5. Confirm cron output artifacts land under `<profile>/cron/output/<job-id>/`.

Minimal recovery used successfully
- copy global `/home/hermes/.hermes/auth.json` into the target profile only when that profile is intended to use the same provider credentials
- add missing fallback API key lines, such as `OPENROUTER_API_KEY=...`, to the target profile `.env`
- retrigger the job and verify `last_status: ok` plus a real session artifact

Why this matters
- A profile-local ticker can be working correctly while the job still fails at agent startup.
- `cron list` alone is not proof; use session/output artifacts and profile-local logs.
