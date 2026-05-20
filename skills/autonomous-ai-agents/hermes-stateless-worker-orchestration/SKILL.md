---
name: hermes-stateless-worker-orchestration
description: Use stateless subagents with structured failure handoffs, explicit retry/replan/decompose escalation, and minimal-context worker prompts for Hermes multi-agent work.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, delegation, multi-agent, orchestration, stateless-workers]
    related_skills: [hermes-agent, subagent-driven-development, systematic-debugging]
---

# Hermes Stateless Worker Orchestration

Use this skill when a task is big enough to benefit from `delegate_task`, spawned Hermes workers, or a coordinator/worker/validator split.

## Core rules

1. Keep workers stateless whenever possible.
   - Give each worker only the task, constraints, and minimal file/context excerpts it needs.
   - Do not dump whole-chat history into subagents.
   - Prefer local `AGENTS.md`, focused file excerpts, and exact error logs over generic background prose.

2. Preserve state in the coordinator, not the workers.
   - The top-level Hermes instance owns planning, task ordering, and synthesis.
   - Workers should return structured results, not become the source of truth.

3. Escalate failures intelligently.
   - Retry once only for transient failures.
   - Otherwise replan or decompose instead of brute-force retrying the same worker prompt.

4. Use cheaper models for workers when quality permits.
   - Keep the strongest/premium model on the coordinator and final validator.
   - Use the configured delegation model for research, coding, extraction, or mechanical subtasks.

## When to use delegate_task vs spawning a full Hermes process

Use `delegate_task` when:
- the work should finish within a bounded subtask
- you want isolation without long-lived state
- the subagent does not need interactive follow-up from the user

Use a spawned Hermes process when:
- the mission is long-running or interactive
- you need a durable terminal session (for example via tmux)
- you want a worktree-isolated agent that may run for hours

## Recommended worker roles

Coordinator
- decomposes the task
- selects worker type and toolset
- decides retry vs replan vs decompose
- synthesizes outputs

Research worker
- toolsets: `web`, optionally `browser`
- job: gather facts, links, source excerpts, uncertainty

Implementation worker
- toolsets: `terminal`, `file`, optionally `code_execution`
- job: make one focused code/config change and report exact artifacts

Validator / reviewer
- toolsets: `file`, optionally `terminal`
- job: verify spec compliance, code quality, test results, or deploy state

## Default worker return schema

Ask workers to return a concise structured block or JSON with:

```json
{
  "status": "success | failed | partial",
  "result_summary": "what happened",
  "artifacts": ["files changed, URLs, commands, outputs"],
  "failure_reason": "empty string if none",
  "tool_trace_summary": "high-level list of tools/commands used",
  "recommended_next_action": "retry | replan | decompose | stop"
}
```

If free-form text is easier, require the same fields in labeled sections.

## Failure escalation policy

### Retry
Use only when the failure is clearly transient, for example:
- flaky network/API timeout
- temporary rate limit
- lock contention that is likely to clear
- browser page hiccup that should succeed on refresh

Retry once with the same plan plus a small corrective note.

### Replan
Use when the worker understood the task but the approach was wrong, for example:
- wrong file or component targeted
- missing prerequisite discovery
- the current toolset is insufficient
- the task needs a different model or different role

### Decompose
Use when the task was too broad or too coupled, for example:
- one worker touched too many files
- research, implementation, and validation were mixed together
- the worker output shows unresolved subproblems

Split into smaller tasks with explicit dependencies.

## Context loading guidance

Prefer this order of context:
1. exact task objective
2. relevant file paths
3. relevant snippets/errors
4. repo-local guidance (`AGENTS.md`, focused docs)
5. constraints and acceptance criteria

Avoid this:
- pasting the entire chat
- duplicating long docs the worker can inspect itself
- loading unrelated files "just in case"

## Suggested prompt template for workers

```text
Goal: <one concrete subtask>

Context:
- repo/project: <name>
- relevant files: <paths>
- constraints: <must/ must not>
- acceptance target: <how success is judged>

Return format:
- status:
- result_summary:
- artifacts:
- failure_reason:
- tool_trace_summary:
- recommended_next_action:
```

## Suggested prompt template for validators

```text
Review this worker result against the stated goal.

Check:
- Did it satisfy the task exactly?
- Are artifacts sufficient and verifiable?
- Is there hidden scope creep?
- If failed, is retry/replan/decompose the right next move?

Return:
- status:
- result_summary:
- artifacts:
- failure_reason:
- tool_trace_summary:
- recommended_next_action:
```

## Practical heuristics

- One file or one subsystem per implementation worker is a good default.
- Use a separate validator when the coordinator also authored the plan.
- If a worker touches deploy/runtime behavior, confirm repo-first application steps before declaring done.
- If several workers need the same large context, stop and create a short shared note instead of repeating long prompts.

## Overnight and long-running missions

For overnight work, do not rely on one immortal conversation.

Preferred pattern:
- keep durable mission state in repo files or shared wiki notes
- run Hermes in repeated bounded passes
- have each pass read the current handoff, do one meaningful chunk, then write back a precise next action
- prefer stateless repeated `hermes chat -q ...` passes over `--continue <session-name>` for first-pass startup reliability; only use explicit session continuation if you have already created and verified the named session
- use auto-compression as a safety net, not as the main continuity mechanism

Recommended components:
- `tmux` for a durable terminal session
- `hermes chat` for each bounded pass
- optional `--continue <session-name>` for continuity
- external handoff files as the source of truth
- cron only for scheduled re-entry or watchdog behavior, not as hidden shared memory
- optional rate-limit behavior control for overnight loops:
  - `fallback` to use normal fallback providers
  - `wait-429` to wait on transient 429-style rate limits while still allowing normal fallback behavior for billing/auth/model-not-found failures
  - `wait` as a backward-compatible alias for `wait-429`

A good overnight pass should:
1. read `handoff.md` and any project-local task state first
2. choose one concrete next action
3. work until that action is done, blocked, or near turn budget
4. retry once only for transient failures
5. otherwise replan or decompose
6. update the handoff with status, artifacts, blockers, and the next exact action before ending

For reusable examples, see the linked templates in this skill directory.
Recommended template set:
- `templates/overnight-handoff.md`
- `templates/overnight-pass-prompt.txt`
- `templates/run-overnight-loop.sh`
- `templates/start-overnight-mission.sh`
- `templates/mission-status.sh`
- `templates/mission-tail.sh`
- `templates/cron-watchdog-prompt.txt`
- `references/overnight-loop-gotchas.md`

## Anti-patterns

Do not:
- ask one worker to research, implement, test, and review everything
- keep retrying a broken plan more than once
- let workers invent their own acceptance criteria
- rely on a worker's prose summary when file/test verification is possible
- treat compression alone as an overnight orchestration strategy
- blur profile boundaries with shared-memory hacks when shared skills/wiki are enough

## Overnight loop implementation pitfalls

- Do not make the bounded overnight loop depend on `hermes chat --continue <session-name>` unless that named session has already been created and verified. Otherwise the loop can fail forever with `No session found matching ...` and make zero progress.
- In loop scripts, derive the base Hermes home from the actual account home directory (for example via `getent passwd $(id -un)`) rather than assuming `$HOME` is trustworthy. Long-running background launches can inherit a profile-local `$HOME` and accidentally build nonsense paths like `<profile-home>/home/.hermes/profiles/<profile>`.
- When using a `recommended next mode: stop` sentinel in the handoff, match only an anchored line, not any instructional mention of the phrase elsewhere in the template. Otherwise the loop can stop immediately before the first real pass.
- After patching overnight loop helpers, verify the next launch from concrete evidence: live child process state plus the first fresh log lines or handoff timestamp. Do not trust only that the parent bash process exists.
