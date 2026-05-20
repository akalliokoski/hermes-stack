# Continuous repo-autoresearch kickoff pattern

Use this when the user says some version of "continuously keep working on X" for a repo-grounded lane.

## Recommended shape

1. Create one recurring cron job for bounded passes.
2. Keep delivery `local` unless the user explicitly wants every pass pushed to chat.
3. If the profile's cron reliability depends on a ticker loop, make sure the ticker is running before trusting schedule metadata.
4. Trigger one immediate kickoff run (`cronjob run` or a one-shot kickoff job) so you can verify real execution now instead of waiting for the next interval.
5. Verify the kickoff from profile-local session artifacts, not only from `cronjob list`.

## Prompt detail that helps

When the lane already has a dirty working tree, tell the loop to:
- inspect `git status --short` first
- prefer finishing or auditing the already-started micro-slice
- avoid opening a fresh branch of work until the in-progress slice is resolved or explicitly parked

## Verification order

1. profile-local cron session file exists, e.g. `~/.hermes/profiles/<profile>/sessions/session_cron_<job_id>_<timestamp>.json`
2. profile-local cron output/session artifacts update over time
3. ticker process is alive if the host needs one
4. only then trust `cronjob list` next-run metadata

## Why this matters

A newly created recurring job can look healthy in scheduler metadata while not yet having produced a real pass. Immediate kickoff plus artifact verification proves the loop actually entered execution and has the right profile/workdir context.
