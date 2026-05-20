# Profile rollout checklist for autoresearch loops

Use this when extending the shared autoresearch-loop pattern to a new Hermes profile.

## 1. Decide stability mode first
- If the profile is experimental and safe to iterate, enable a bounded recurring loop plus a one-shot kickoff.
- If the profile is stability-sensitive, create the prompt/wiki scaffolding and kickoff artifacts first, but keep the recurring loop paused or disabled until the user explicitly wants it active.

## 2. Create profile-local durable notes before relying on the loop
- If the repo already has a wiki/notes layer, point the loop at it.
- If the repo has no durable notes yet, scaffold a minimal local wiki in the workspace:
  - `wiki/SCHEMA.md`
  - `wiki/index.md`
  - `wiki/log.md`
- The loop prompt should require reading schema/index/recent log first and updating the log on each meaningful pass.

## 3. Verify profile-local runtime, not just the global home
- Confirm the intended `HERMES_HOME` for the profile.
- Check profile-local `auth.json` or equivalent provider auth path.
- Check profile-local `.env` for provider keys the runtime may need.
- Verify cron session/output artifacts land under the correct profile home.

## 4. Prefer service-managed tickers, but respect approval boundaries
- Best durable setup on a VPS: a dedicated profile-specific ticker service running native `hermes cron tick --accept-hooks` with the correct `HOME`, `HERMES_HOME`, and `WorkingDirectory`.
- If service installation is blocked by the command-approval layer or missing sudo approval:
  - do not retry blindly
  - write the service unit into the repo/workspace
  - write a small install helper script into the repo/workspace
  - verify those files are executable/readable
  - clearly report that installation is still pending approval
  - if an existing background ticker is already working, leave it in place as the temporary runtime until the user approves installation

## 5. Verify health from artifacts
Trust, in order:
1. profile-local cron session files
2. profile-local cron output artifacts
3. live process/service state
4. only then status/list output

## 6. Default/global profile caution
For the `default` profile, avoid assuming the recurring loop should stay enabled. If the user wants the default profile kept stable, pause the loop after setup and leave only the prompt/docs scaffolding in place until re-enabled.
