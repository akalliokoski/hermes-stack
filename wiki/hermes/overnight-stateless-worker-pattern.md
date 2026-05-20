# Overnight stateless worker pattern

This note is intended to be shared across Hermes profiles.

## Best pattern

Use repeated bounded Hermes passes, not one immortal session.

Core pieces:
- a durable terminal session such as tmux
- `hermes chat` for one bounded pass at a time
- a handoff file as the source of truth
- optional `--continue <session-name>` for continuity
- auto-compression left enabled as a safety net

## Why

This survives turn caps, reduces context drift, and keeps mission state outside any single session.

## Shared skill assets

Skill directory:
- `~/.hermes/shared/skills/autonomous-ai-agents/hermes-stateless-worker-orchestration/`

Templates:
- `templates/overnight-handoff.md`
- `templates/overnight-pass-prompt.txt`
- `templates/run-overnight-loop.sh`
- `templates/start-overnight-mission.sh`
- `templates/mission-status.sh`
- `templates/mission-tail.sh`
- `templates/cron-watchdog-prompt.txt`

## Rate-limit behavior modes

The loop now supports three names but two real behaviors:

- `--rate-limit-mode fallback`
  - use the profile's normal `fallback_providers`
  - if the primary model is rate-limited, Hermes may switch to a configured fallback provider

- `--rate-limit-mode wait-429`
  - first try the pass with `fallback_providers` removed in a temporary runtime overlay
  - if the output looks like a transient 429-style rate limit, sleep and retry the primary model later
  - if the failure instead looks like billing/auth/model-not-found, rerun the pass once with normal fallback providers enabled

- `--rate-limit-mode wait`
  - backward-compatible alias for `wait-429`

This stays shareable across profiles because the wrapper derives the real profile home and builds only a temporary per-run overlay from it.

## Recommended setup per mission

1. Create a mission directory inside the project workspace.
2. Copy or initialize the handoff template there.
3. Fill in the goal, repo path, constraints, and next exact action.
4. Launch the loop inside tmux.
5. Inspect `handoff.md` and `overnight.log` in the morning.

## Easiest starter command

```bash
HERMES_PROFILE=gemma \
~/.hermes/shared/skills/autonomous-ai-agents/hermes-stateless-worker-orchestration/templates/start-overnight-mission.sh \
  --rate-limit-mode wait-429 \
  --stop-on-mode-stop \
  /path/to/project/.hermes-mission \
  gemma-overnight-session
```

This creates if missing:
- `/path/to/project/.hermes-mission/handoff.md`
- `/path/to/project/.hermes-mission/goal.txt`
- `/path/to/project/.hermes-mission/overnight.log`

Then edit `goal.txt` and `handoff.md`, and attach later with:

```bash
tmux attach -t gemma-overnight-session
```

To inspect status quickly without opening tmux:

```bash
~/.hermes/shared/skills/autonomous-ai-agents/hermes-stateless-worker-orchestration/templates/mission-status.sh \
  /path/to/project/.hermes-mission
```

To follow the mission log live:

```bash
~/.hermes/shared/skills/autonomous-ai-agents/hermes-stateless-worker-orchestration/templates/mission-tail.sh \
  /path/to/project/.hermes-mission
```

## Direct loop example

```bash
tmux new-session -d -s gemma-overnight '\
  HERMES_PROFILE=gemma \
  ~/.hermes/shared/skills/autonomous-ai-agents/hermes-stateless-worker-orchestration/templates/run-overnight-loop.sh \
  --rate-limit-mode wait-429 \
  --stop-on-mode-stop \
  gemma-overnight-session \
  /path/to/project/handoff.md \
  /path/to/project/goal.txt'
```

If you want another profile later, change only `HERMES_PROFILE` and the session name.

## Cron watchdog guidance

Use cron only when the cron runtime can see the same project paths.
If path visibility is uncertain, prefer tmux.

Prompt template:
- `templates/cron-watchdog-prompt.txt`

## Notes

- Prefer project-local handoff files over profile-local hidden state.
- Use `hermes -w` manually for parallel coding agents when git isolation matters.
- Use cron only for scheduled re-entry or watchdog behavior, not as the only state mechanism.
- `--rate-limit-mode wait-429` disables configured fallback providers only for the first attempt of that pass; on billing/auth/model-not-found style failures it reruns once with normal fallback behavior. It does not permanently change the profile config.
