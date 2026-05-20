---
name: autoresearch-loop
description: "Profile-agnostic bounded autoresearch loop for repo-grounded recurring research, experiment iteration, and cron-driven maintenance without modifying Hermes core code."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [autoresearch, cron, research, workflow, git, experiments]
    related_skills: [hermes-agent, llm-wiki]
---

# Autoresearch Loop

## Overview

Use this skill when a profile needs the autoresearch pattern but should not depend on Hermes source-code changes.

The loop should be built from native Hermes primitives only:
- skills
- cron jobs
- repo/workdir state
- profile-local or shared docs/wiki
- host-native service management when needed for ticker durability

This skill is intentionally profile-agnostic. It defines the loop shape, not the project domain. Pair it with profile-specific skills and prompts for the actual subject matter.

## When to use

Use this when:
- you want recurring repo-grounded research or experiment passes
- you want bounded autonomous progress with written handoffs
- you want a cron-driven loop that updates durable notes/docs
- you want the same operating pattern reused across multiple Hermes profiles

Do not use this when:
- there is no inspectable workdir or repo
- the task requires frequent user choices mid-run
- the task has no measurable or reviewable success condition
- you need a heavyweight external scheduler instead of a bounded agent loop

## Core pattern

Each pass should:
1. inspect current repo/docs/wiki state first
2. choose exactly one primary increment
3. make one bounded change or one bounded research/documentation increment
4. record evidence and a handoff
5. preserve findings in durable artifacts instead of chat alone

## Cron job shape

Recommended defaults:
- schedule: every 30m to 120m depending on urgency
- workdir: the target repo root
- deliver: local by default
- tools: only what the pass actually needs
- repeat: bounded when testing, unbounded only after the loop proves reliable

For active debugging or tight iteration, prefer:
- every 30m
- one primary increment per pass
- a finite run budget first

For actual overnight work, do not stop at a single successful bounded pass and call it an overnight run.
Use a recurring loop with multiple scheduled passes plus a separate morning synthesis handoff.
Good default shape:
- 6-10 passes overnight
- one bounded increment plus self-audit per pass
- local delivery for intermediate passes to avoid noise
- a one-shot morning summary job delivered back to the user/origin

If the first pass is only a smoke test or scaffold pass, explicitly say so and keep the recurring job running unless the mission handoff reaches a real `review` or `stop` gate.
A valid bounded pass may also be a no-code verification pass when the queued target is already clean: verify the target from filesystem evidence, record that no body edits were needed, and advance the next exact queued target instead of forcing churn just to make the pass look active.

## Kickoff pattern

When starting a new campaign:
- create the recurring loop job
- also create a separate one-shot kickoff job 1-2 minutes ahead when you need immediate verification, or manually `run` the new recurring job once right after creation if that is the fastest reliable path
- for overnight runs, also create a one-shot morning summary/synthesis job tied to the recurring loop context
- verify the jobs exist
- verify execution from concrete artifacts, not scheduler metadata alone
- if the repo already has a dirty working tree on the target lane, bias the loop prompt toward finishing or auditing the in-progress slice before opening a new branch of work

Practical verification rule:
- after `run`/kickoff, look for the new cron session/output artifact under the profile-local Hermes home (for example `~/.hermes/profiles/<profile>/sessions/session_cron_<job>_*.json`) in addition to checking job metadata

This matters because overdue interval jobs may fast-forward after ticker downtime instead of replaying missed passes.

## Durability pattern

If scheduled jobs do not fire reliably, do not patch Hermes core code.

Instead:
1. verify the profile-specific `HERMES_HOME`
2. inspect profile-local cron/session files
3. run or restore a profile-local ticker using native `hermes cron tick --accept-hooks`
4. when host service management is available, prefer a dedicated service for the ticker over an ad-hoc shell background loop

## Hybrid pattern with Kanban

Use autoresearch as the default engine for sequential bounded progress, and Kanban only when the work needs durable decomposition.

Good default split:
- **Autoresearch cron/manual pass**: inspect repo state, choose one primary increment, patch/run/analyze/document
- **Kanban board**: branch points, parallel comparisons, reviewer gates, human unblock points, and campaign-level handoffs

Practical coexistence rule:
- It is safe to seed or plan a Kanban board while the autoresearch cron loop is still running.
- Before dispatching **repo-mutating Kanban tasks** that will edit or rerun the same project surface, pause the overlapping autoresearch cron loop unless you explicitly want concurrent autonomous work on the same repo.
- Before a human-directed manual review/commit/push session on the same workspace, pause overlapping repo-mutating cron jobs first. Resume or replace the loop only after the manual mutation window closes.
- Read-only Kanban tasks such as literature review, audit planning, or campaign synthesis can coexist with the cron loop more safely, but still call out the shared context in the handoff.

Recommended service properties:
- run as the Hermes user
- set `HOME` correctly
- set the profile-specific `HERMES_HOME`
- set `WorkingDirectory` to the target repo/workdir
- restart automatically
- ensure the profile-local Hermes home actually has usable auth/config/env, not just the global home

Before declaring a profile-local loop healthy, verify:
- the target profile has its own `auth.json` or another valid credential path for the selected provider
- the target profile `.env` includes any fallback provider keys the runtime may need
- cron-created session/output artifacts appear under that profile home, not only in the global home

## Prompt design rules

A loop prompt should include:
- objective
- repo/workdir path
- files/docs to inspect first
- allowed edit scope
- success criterion
- stop condition
- bookkeeping requirements
- required output sections

If the profile maintains a wiki or durable notes layer, require the pass to:
- inspect schema/index/recent log first
- append a chronological log entry every pass
- update durable pages when understanding materially changes

## Output contract

Require each pass to end with:
- Current bottleneck
- What I inspected
- What I changed or decided not to change
- Evidence
- Founder learning digest when the topic is new, implementation-heavy, or technically specialized:
  - what changed
  - the new terms/concepts in plain language
  - why it matters for the project
  - what remains uncertain
  - what evidence the user can inspect
  - what the user needs to learn next to validate the result
  - whether a visual/dashboard artifact exists; if not, say so and propose/create one when visual tracking is a blocker
- Best next experiment
- Exact files touched or to touch next
- Stop/continue recommendation

When the user has limited domain background, follow `references/beginner-learning-evidence-handoff.md` and treat beginner-readable metric explanations, source/resource shelves, and learning prerequisites as part of the deliverable, not as optional commentary.

## Verification order

Trust evidence in this order:
1. cron-created session files
2. live process/service state
3. generated artifacts/logs
4. only then cron metadata/status output

Reference notes:
- `references/continuous-kickoff-and-session-verification.md` — continuous "keep working on X" pattern: recurring cron creation, immediate kickoff run, dirty-worktree-first prompting, and session-artifact verification
- `references/profile-local-auth-and-env.md` — profile-local credential/env failure mode when loops are moved under a profile-specific `HERMES_HOME`
- `references/profile-rollout-checklist.md` — rollout checklist for enabling the loop on additional profiles, including wiki scaffolding, stability-sensitive default-profile handling, and approval-blocked service installs
- `references/synthetic-data-campaign-and-evolution-ui.md` — pattern for simulation/synthetic-data autoresearch campaigns: multi-objective metrics, one-change passes, worst-case artifact checks, campaign artifacts, Kanban branch shape, and report-backed evolution UI
- `references/biosignal-reference-ui-pattern.md` — pattern for adding public/reference biosignal snippets to synthetic-data evolution UIs as orientation context without upgrading validation, clinical, hardware, privacy, or accepted-baseline claims
- `references/beginner-learning-evidence-handoff.md` — required handoff pattern for technical scheduled/overnight work: explain actual work, metric meanings, evidence paths, learning prerequisites, source shelf, and visual/progress surfaces for beginner validation
- `references/markdown-link-hardening.md` — verification pattern for markdown-link autoresearch passes: filesystem link-resolution audit, body-vs-frontmatter exceptions, no-op verification passes, and commit/push gating when cron work overlaps with manual review

## Cross-profile reuse rule

Keep this shared skill generic.

Per-profile specialization should live in:
- the cron prompt itself
- profile-local wiki/docs
- profile-local project skills
- profile-local env/config

When rolling the loop out to a new profile:
1. decide whether the profile should be active immediately or kept paused for stability
2. scaffold durable notes first if the workspace has no wiki/log structure yet
3. verify profile-local auth/env under the intended `HERMES_HOME`
4. prefer a dedicated profile-specific ticker service for durability
5. if service installation is blocked by approval or sudo boundaries, prepare repo-owned service/install artifacts and leave any working temporary ticker in place until approval is granted

That lets multiple profiles reuse the same autoresearch loop architecture without coupling them to ai-lab-specific assumptions.

## Pitfalls

- do not treat lower loss, average F1, or generic status output as proof of success; inspect worst-split/worst-artifact behavior and claim-safety guardrails
- when bulk-rewriting markdown links, do not trust regex-only counts or markdown appearance alone; run a filesystem link-resolution audit over the changed docs and keep placeholders/nonexistent planned artifacts as plain text
- if a loop surfaced changes that will be manually reviewed and committed, do not leave the overlapping repo-mutating cron job active during review; pause it first to avoid racing edits and misleading handoffs
- for synthetic biosignal campaigns, do not treat public/reference signal snippets as validation proof; keep them in a separate reference-context panel with source/license/provenance/caveats, and never let them alter accepted-baseline status without a pre-registered reviewed gate
- do not add learned baselines to synthetic-data campaigns without a pre-registered split-lock and validation/test protocol
- do not mix multiple conceptual changes into one pass unless the run is explicitly exploratory
- do not rely on chat-only conclusions
- do not assume a generic gateway process proves profile-local cron health
- do not remove bounded run caps until the loop has passed a real reliability test
- do not run a repo-mutating autoresearch cron loop in parallel with an active Kanban campaign that edits the same workspace; pick one control plane at a time
- for synthetic biosignal campaigns, do not imply a synthetic generator exists just because a real-reference adapter or TRTR baseline exists; label TRTR/TSTR/TRTS explicitly, and prefer an auditable parametric physiology-inspired first generator before GAN/diffusion/transformer work unless a pre-registered protocol justifies the learned model
- for synthetic biosignal campaigns, do not treat public/reference signal snippets as validation proof; keep them in a separate reference-context panel with source/license/provenance/caveats, and never let them alter accepted-baseline status without a pre-registered reviewed gate
- if Kanban becomes the primary orchestrator for a campaign, pause overlapping repo-mutating cron jobs and let cron only handle safe non-overlapping duties such as dispatch, monitoring, or periodic non-mutating audits
