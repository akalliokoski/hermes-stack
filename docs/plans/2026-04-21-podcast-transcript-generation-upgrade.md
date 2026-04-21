# Podcast Transcript Generation Upgrade Implementation Plan

> For Hermes: use `software-development/subagent-driven-development` if executing this plan later.

Goal: Upgrade the hermes-stack podcast pipeline so transcript generation produces more natural, Chatterbox-aware dialogue with explicit per-turn metadata, validation, and archival, while staying backend-agnostic and repo-first.

Architecture: Keep the thin shared `podcast-pipeline` skill as orchestration guidance, but move transcript quality improvements into hermes-stack runtime code under `scripts/`. Introduce a structured transcript artifact (`transcript.json`) as the canonical source of truth, a two-pass transcript generation flow, validation/audit helpers, and a compatibility layer that can still emit Podcastfy-compatible dialogue today while preparing for a future direct Chatterbox turn-by-turn renderer.

Tech Stack: Python CLI helpers in `scripts/`, existing Hermes CLI invocation, stdlib JSON/regex/dataclasses, existing wiki archival helpers, current Modal/OpenAI-compatible Chatterbox backend, current podcastfy integration as compatibility mode.

---

## 1. Why this plan is different from the copied one

The copied plan assumed a new standalone Hermes skill directory that directly owns transcript generation and then feeds a custom turn-by-turn Chatterbox renderer.

For our project, the real runtime lives in `/home/hermes/work/hermes-stack`, and the shared `podcast-pipeline` skill is intentionally thin. So the right adaptation is:

- keep the skill thin and update it later to describe the new behavior
- implement the transcript-generation upgrade in repo scripts first
- preserve current working podcastfy flow while improving transcript quality immediately
- add a structured transcript format now so we can later bypass podcastfy without redesigning the transcript layer again

This matches repo conventions in `AGENTS.md`: fix the repo, not just the live host, and keep operational logic auditable in hermes-stack.

---

## 2. Current state in hermes-stack

### Existing runtime files
- `scripts/make-podcast.py`
  - prompts Hermes once for a transcript
  - expects final output to be raw `<Person1>` / `<Person2>` blocks
  - archives transcript text to the wiki
  - hands transcript to podcastfy
- `scripts/run_podcastfy_pipeline.py`
  - normalizes `HOST_A:` / `HOST_B:` lines to `<Person1>` / `<Person2>`
  - runs `podcastfy.client --transcript ... --tts-model openai`
  - renames emitted MP3 to final filename
- `scripts/podcast_pipeline_common.py`
  - shared output paths, slugging, env loading, wiki archival
- shared skill: `~/.hermes/skills/media/podcast-pipeline/SKILL.md`
  - documents the current generic transcript generation flow

### Current limitations to eliminate
1. Transcript generation is single-pass and generic.
2. There is no canonical structured transcript object; only text blocks exist.
3. Chatterbox-specific strengths are not encoded in the transcript prompt.
4. There is no transcript audit step for voice differentiation, tag validity, or emotion arc.
5. Emotion/exaggeration metadata does not exist yet, so future direct Chatterbox rendering would require a transcript redesign.
6. The existing pipeline archives only one final transcript text artifact, not structured transcript metadata plus audit results.

---

## 3. Target design for our project

### Canonical transcript artifact
Introduce a JSON transcript as the source of truth for generation and validation:

```json
{
  "version": 1,
  "title": "AI Research Weekly",
  "episode_slug": "2026-04-21_ai-research-weekly",
  "show_slug": "ai-research-weekly",
  "duration_hint": "medium",
  "generation_mode": "podcastfy_compat",
  "hosts": {
    "HOST_A": {
      "role": "connector",
      "default_emotion": 0.8,
      "podcastfy_speaker": "Person1"
    },
    "HOST_B": {
      "role": "interrogator",
      "default_emotion": 0.75,
      "podcastfy_speaker": "Person2"
    }
  },
  "turns": [
    {
      "turn_id": "t01",
      "speaker": "HOST_A",
      "text": "The weird thing is that memory used to feel like a feature. Now it feels like infrastructure. [chuckle]",
      "emotion": 0.82,
      "tags": ["chuckle"],
      "notes": ["cold_open", "topic_intro"]
    }
  ]
}
```

### Derived artifacts
The pipeline should derive, not author by hand:
- `transcript.json` — canonical structured artifact
- `transcript.txt` or `.xml` — Podcastfy-compatible `<Person1>/<Person2>` transcript generated from JSON
- `transcript-audit.json` — audit results and warnings
- wiki archives for the structured transcript and rendered transcript text

### Compatibility strategy
Phase the work so we get better transcripts without immediately rewriting audio synthesis:

1. Near-term: generate better structured transcript JSON, audit it, render it to Podcastfy-compatible dialogue, keep current `run_podcastfy_pipeline.py` flow.
2. Later: add a direct Chatterbox turn renderer that uses per-turn `emotion` and inline tags directly, then optionally retire podcastfy for podcast episodes.

That means the transcript upgrade is useful immediately and not blocked on the renderer migration.

---

## 4. Transcript craft rules adapted to hermes-stack

### Host identities
Keep these in the repo as prompt/reference data instead of burying them inside one giant prompt string.

HOST_A — The Connector
- opens threads and adds context
- slightly longer sentences
- bridges topics and frames stakes
- occasional self-correction or clarification
- default emotion around 0.8

HOST_B — The Interrogator
- shorter, punchier responses
- pressure-tests claims
- uses interruptions and reframings
- drives pivots and tension
- default emotion around 0.75

### Episode structure
Default arc for source-driven episodes:
- cold open: 1-2 turns
- context frame: 2-3 turns
- topic 1: 6-8 turns
- pivot: 1-2 turns
- topic 2: 6-8 turns
- synthesis: 3-4 turns
- close: 1-2 turns

Avoid sterile intro/outro boilerplate like “welcome back” or “that’s all for today” unless the user explicitly wants it.

### Allowed Chatterbox-oriented inline tags
Support only the explicitly approved tags in repo validation logic:
- `[laugh]`
- `[chuckle]`
- `[sigh]`
- `[gasp]`
- `[cough]`

Rules:
- tag must appear after a completed clause or sentence
- do not stack multiple tags in a row
- do not overuse tags
- `[gasp]` should be extremely rare
- `[cough]` should usually be flagged as suspicious, not encouraged

### Emotion guidance
Store numeric `emotion` values per turn now, even before the audio path consumes them fully.

Suggested bands:
- `0.5` dry factual delivery
- `0.7` ordinary conversational engagement
- `0.85` animated explanation
- `1.0` key insight or peak emphasis
- `>1.0` only for clearly earned moments

For the current podcastfy compatibility path, these values are archived and audited even if not yet forwarded to podcastfy. For a future direct renderer, these map to Chatterbox `exaggeration`.

---

## 5. Target file/module layout

### Modify
- `scripts/make-podcast.py`
- `scripts/run_podcastfy_pipeline.py`
- `scripts/podcast_pipeline_common.py`
- `tests/` (new podcast transcript tests)
- `SETUP.md`
- `~/.hermes/skills/media/podcast-pipeline/SKILL.md` after repo changes are working

### Create
- `scripts/podcast_transcript_schema.py`
  - dataclasses/schema helpers
  - JSON load/save
  - transcript normalization helpers
- `scripts/podcast_transcript_prompting.py`
  - prompt builders for draft and revision passes
  - host profile/reference injection
- `scripts/podcast_transcript_audit.py`
  - structural and quality checks
  - emotion-arc checks
  - tag validation and overuse warnings
- `scripts/render_podcast_transcript.py`
  - convert canonical JSON into Podcastfy-compatible `<Person1>/<Person2>` blocks
  - later extend for direct turn-by-turn Chatterbox mode
- `tests/test_podcast_transcript_schema.py`
- `tests/test_podcast_transcript_audit.py`
- `tests/test_render_podcast_transcript.py`
- `docs/plans/2026-04-21-podcast-transcript-generation-upgrade.md` (this plan; keep updated if scope changes materially)

Optional but recommended later:
- `scripts/run_chatterbox_turn_pipeline.py`
  - direct per-turn synthesis and stitching for full Chatterbox-aware audio output

### Optional prompt/reference assets
If the prompts get large, prefer explicit text assets under the repo rather than giant inline strings:
- `scripts/references/podcast_host_profiles.md`
- `scripts/references/podcast_transcript_rules.md`

Do not create a second skill directory for runtime logic. Keep runtime logic in the repo.

---

## 6. Canonical generation flow

### New flow inside `make-podcast.py`
1. Collect source files, URLs, topic, notes exactly as today.
2. Build a source packet summary for prompting.
3. Run draft transcript generation via Hermes, requesting canonical JSON.
4. Validate/parse JSON.
5. Run revision pass via Hermes with the draft JSON plus explicit audit rubric.
6. Run local audit helpers on the revised JSON.
7. Fail hard on schema errors; warn but continue on soft craft warnings.
8. Archive both structured transcript and rendered dialogue transcript to the wiki.
9. Render canonical JSON into Podcastfy-compatible `<Person1>/<Person2>` transcript.
10. Feed the rendered transcript to `run_podcastfy_pipeline.py`.

### Why two passes
The second pass is the cheapest way to improve quality without needing a second model family or a full evaluator loop. Draft first for content coverage, revise second for voice separation, pacing, and Chatterbox-aware tags/emotion.

---

## 7. Concrete implementation tasks

### Task 1: Add canonical transcript schema helpers

Objective: Create one structured transcript format and helpers that everything else uses.

Files:
- Create: `scripts/podcast_transcript_schema.py`
- Create: `tests/test_podcast_transcript_schema.py`

Step 1: Write failing tests
Add tests for:
- parsing valid transcript JSON into an internal object/dict
- rejecting missing `turns`
- rejecting unknown speaker labels
- rejecting non-numeric or out-of-range `emotion`
- extracting inline tags from turn text
- preserving deterministic output ordering when saving JSON

Step 2: Run tests to verify failure
Run:
```bash
pytest tests/test_podcast_transcript_schema.py -q
```
Expected: failure because module does not exist.

Step 3: Implement minimal schema helpers
Include:
- `ALLOWED_CHATTERBOX_TAGS = {"laugh", "chuckle", "sigh", "gasp", "cough"}`
- `load_transcript_json(path)`
- `save_transcript_json(path, data)`
- `validate_transcript(data)`
- `extract_inline_tags(text)`
- `episode_slug_for_title(title)`

Keep implementation stdlib-only.

Step 4: Run tests to verify pass
Run:
```bash
pytest tests/test_podcast_transcript_schema.py -q
```
Expected: pass.

Step 5: Commit
```bash
git add scripts/podcast_transcript_schema.py tests/test_podcast_transcript_schema.py
git commit -m "feat: add podcast transcript schema helpers"
```

---

### Task 2: Add transcript audit and quality checks

Objective: Encode the craft rules locally so transcript quality is not prompt-only.

Files:
- Create: `scripts/podcast_transcript_audit.py`
- Create: `tests/test_podcast_transcript_audit.py`
- Modify: `scripts/podcast_transcript_schema.py`

Step 1: Write failing tests
Add tests for:
- flagging unknown inline tags
- flagging overuse of `[gasp]`
- flagging more than N total paralinguistic tags per short episode
- warning when one speaker dominates turn count too heavily
- warning when emotion values are flat across all turns
- warning when the peak emotion occurs too early or not at all

Step 2: Run tests to verify failure
Run:
```bash
pytest tests/test_podcast_transcript_audit.py -q
```
Expected: failure because module does not exist.

Step 3: Implement audit helpers
Include:
- `audit_transcript(data) -> dict`
- `validate_tag_placement(text) -> list[str]`
- `emotion_arc_summary(turns) -> dict`
- `speaker_balance_summary(turns) -> dict`
- severity levels: `error`, `warning`, `info`

Hard-fail only on structural invalidity. Keep craft checks mostly warning-level so source-constrained episodes can still ship.

Step 4: Run tests to verify pass
Run:
```bash
pytest tests/test_podcast_transcript_audit.py -q
```
Expected: pass.

Step 5: Commit
```bash
git add scripts/podcast_transcript_audit.py scripts/podcast_transcript_schema.py tests/test_podcast_transcript_audit.py
git commit -m "feat: add podcast transcript audit checks"
```

---

### Task 3: Add transcript renderer for Podcastfy compatibility

Objective: Convert canonical JSON into the exact `<Person1>/<Person2>` text that today’s audio pipeline expects.

Files:
- Create: `scripts/render_podcast_transcript.py`
- Create: `tests/test_render_podcast_transcript.py`
- Modify: `scripts/run_podcastfy_pipeline.py`

Step 1: Write failing tests
Add tests for:
- rendering HOST_A to `<Person1>` and HOST_B to `<Person2>`
- preserving inline tags in text output
- skipping empty turns
- normalizing whitespace cleanly
- optionally writing both rendered text and sidecar metadata

Step 2: Run tests to verify failure
Run:
```bash
pytest tests/test_render_podcast_transcript.py -q
```
Expected: failure because module does not exist.

Step 3: Implement renderer
Include:
- `render_for_podcastfy(data) -> str`
- `render_turn(turn, hosts) -> str`
- CLI flags so the script can read `transcript.json` and emit `transcript.txt`

Update `run_podcastfy_pipeline.py` so it can accept either:
- existing raw transcript text as today
- canonical `transcript.json` and auto-render it before invoking podcastfy

This preserves backward compatibility with current transcripts.

Step 4: Run tests to verify pass
Run:
```bash
pytest tests/test_render_podcast_transcript.py -q
```
Expected: pass.

Step 5: Commit
```bash
git add scripts/render_podcast_transcript.py scripts/run_podcastfy_pipeline.py tests/test_render_podcast_transcript.py
git commit -m "feat: render canonical podcast transcripts for podcastfy"
```

---

### Task 4: Refactor `make-podcast.py` to generate structured transcripts in two passes

Objective: Replace the current one-shot generic prompt with draft + revision JSON generation.

Files:
- Modify: `scripts/make-podcast.py`
- Create: `scripts/podcast_transcript_prompting.py`
- Modify: `scripts/podcast_pipeline_common.py`

Step 1: Write failing tests
Add targeted tests for helper-level behavior, not end-to-end TTS:
- draft prompt contains host profile rules and source references
- revision prompt includes explicit audit rubric and draft transcript
- generated files include `transcript.json`, rendered `transcript.txt`, and `transcript-audit.json`
- wiki archival is called for both structured and rendered transcript artifacts

If full unit coverage is awkward, at minimum add pure-function tests around prompt builders and transcript artifact path helpers.

Step 2: Run tests to verify failure
Run:
```bash
pytest tests/test_podcast_transcript_schema.py tests/test_podcast_transcript_audit.py tests/test_render_podcast_transcript.py -q
```
Expected: some failures or missing integration helpers.

Step 3: Implement prompt builders and integration
Refactor `make-podcast.py` so that:
- `build_generation_prompt(...)` becomes draft-prompt logic in `podcast_transcript_prompting.py`
- add `build_revision_prompt(...)`
- Hermes is called twice when generating from source material
- the script validates draft JSON before revision
- the script writes:
  - temporary or output `transcript-draft.json`
  - final `transcript.json`
  - `transcript-audit.json`
  - rendered Podcastfy transcript text
- dry-run mode prints artifact paths and audit summary cleanly

Do not break `--transcript` for users supplying an existing transcript manually.

Step 4: Run tests to verify pass
Run:
```bash
pytest tests/test_podcast_transcript_schema.py tests/test_podcast_transcript_audit.py tests/test_render_podcast_transcript.py -q
```
Expected: pass.

Step 5: Manual verification
Run a dry run with a small inline topic:
```bash
python scripts/make-podcast.py \
  --title "Transcript Upgrade Smoke Test" \
  --topic "Why agent memory matters" \
  --dry-run
```
Expected:
- `transcript.json` generated
- `transcript-audit.json` generated
- rendered transcript text generated
- no TTS invocation in dry-run mode

Step 6: Commit
```bash
git add scripts/make-podcast.py scripts/podcast_transcript_prompting.py scripts/podcast_pipeline_common.py
git commit -m "feat: add two-pass structured podcast transcript generation"
```

---

### Task 5: Improve archival and provenance

Objective: Archive transcript artifacts so future review and reuse are easy.

Files:
- Modify: `scripts/podcast_pipeline_common.py`
- Modify: `scripts/make-podcast.py`
- Optionally create: `tests/test_podcast_pipeline_common.py`

Step 1: Write failing tests
Add tests for:
- structured transcript archive path under `raw/transcripts/media/podcasts/`
- audit sidecar archive naming
- rendered transcript archive naming
- provenance block includes pipeline name and title

Step 2: Run tests to verify failure
Run:
```bash
pytest tests/test_podcast_pipeline_common.py -q
```
Expected: failure if new helper does not exist yet.

Step 3: Implement archival refinements
Add helpers such as:
- `archive_generated_json(...)`
- or extend `archive_generated_text(...)` cleanly without abusing markdown wrappers

Recommended final archived files per episode:
- `YYYY-MM-DD_<slug>-transcript-structured.json`
- `YYYY-MM-DD_<slug>-transcript-audit.json`
- `YYYY-MM-DD_<slug>-transcript-rendered.md`

Step 4: Run tests to verify pass
Run:
```bash
pytest tests/test_podcast_pipeline_common.py -q
```
Expected: pass.

Step 5: Commit
```bash
git add scripts/podcast_pipeline_common.py scripts/make-podcast.py tests/test_podcast_pipeline_common.py
git commit -m "feat: archive structured podcast transcript artifacts"
```

---

### Task 6: Document the upgraded behavior and update the thin skill

Objective: Align docs and the shared skill with the new repo behavior.

Files:
- Modify: `SETUP.md`
- Modify: `/home/hermes/.hermes/skills/media/podcast-pipeline/SKILL.md`
- Modify: `docs/plans/2026-04-21-podcast-transcript-generation-upgrade.md` if scope shifted during implementation

Step 1: Update `SETUP.md`
Document:
- canonical transcript JSON format
- two-pass generation flow
- audit sidecars
- current compatibility mode with podcastfy
- future direct Chatterbox renderer as optional next step, not current behavior

Step 2: Update the shared skill
Change the skill from “Hermes generates a concise transcript” to “Hermes generates, revises, validates, archives, and renders a structured transcript before audio synthesis”.

Keep the skill thin. Do not duplicate runtime code or giant prompt text there.

Step 3: Verify docs match code
Read both files and compare against actual helper names and paths.

Step 4: Commit
```bash
git add SETUP.md docs/plans/2026-04-21-podcast-transcript-generation-upgrade.md
git commit -m "docs: document upgraded podcast transcript pipeline"
```

---

## 8. Prompt contract for Hermes generation

### Draft-pass requirements
Ask Hermes to return only canonical JSON with:
- no markdown fences
- no commentary
- exactly two speakers: `HOST_A`, `HOST_B`
- grounded content based only on supplied source packet
- inline allowed tags only
- per-turn `emotion`
- natural but information-dense conversational pacing

### Revision-pass requirements
Pass in:
- the same source packet summary
- the draft JSON
- explicit rewrite checks:
  - make speakers more distinct
  - remove “as you know” exposition
  - make every exchange do at least two jobs where possible
  - smooth emotion arc
  - reduce tag overuse
  - keep claims grounded in source material

### Failure handling
If Hermes returns invalid JSON:
- first attempt one repair pass that asks Hermes to repair structure only
- if still invalid, fail the run clearly with the raw response saved for debugging

Do not silently coerce broken JSON into something else.

---

## 9. Acceptance criteria

The plan is complete when all of the following are true:

1. `make-podcast.py --dry-run` can generate a canonical `transcript.json` plus audit artifacts from source material.
2. The pipeline still supports existing user-supplied transcript text files.
3. `run_podcastfy_pipeline.py` can consume either old text transcripts or new canonical JSON transcripts.
4. Inline tags are validated against an explicit allowlist.
5. Emotion values are present and audited for arc quality.
6. Structured transcript artifacts are archived into the shared wiki.
7. `SETUP.md` and the thin `podcast-pipeline` skill document the new behavior accurately.
8. No new non-stdlib Python dependency is introduced just for transcript generation or auditing.

---

## 10. Verification checklist

Before claiming success on implementation:

1. Run targeted unit tests:
```bash
pytest tests/test_podcast_transcript_schema.py tests/test_podcast_transcript_audit.py tests/test_render_podcast_transcript.py -q
```

2. Run a dry-run integration check:
```bash
python scripts/make-podcast.py \
  --title "Transcript Upgrade Smoke Test" \
  --topic "Why agent memory matters" \
  --dry-run
```

3. Inspect generated artifacts for:
- valid JSON structure
- distinct host voices
- reasonable tag use
- non-flat emotion arc
- clean rendered `<Person1>/<Person2>` output

4. Run one real end-to-end episode after dry-run passes:
```bash
python scripts/make-podcast.py \
  --title "Transcript Upgrade Real Test" \
  --topic "Why agent memory matters" \
  --tts-base-url "$TTS_BASE_URL"
```

5. Confirm:
- MP3 exists under `/data/audiobookshelf/podcasts/ai-generated/<show-slug>/`
- structured transcript artifacts are archived in the wiki
- Audiobookshelf scan still succeeds best-effort

---

## 11. Non-goals for this plan

Do not bundle these into the first implementation pass:
- replacing podcastfy immediately
- building speaker-specific voice cloning volumes or voice routing changes
- adding a third host
- adding a GUI editor for transcript JSON
- implementing a full evaluator framework with model-graded scoring

Those are follow-on tasks once the structured transcript layer is in place.

---

## 12. Recommended next plan after this one

Once this transcript upgrade lands, the natural follow-up is:
- add `scripts/run_chatterbox_turn_pipeline.py`
- synthesize one turn at a time using the canonical JSON
- pass `emotion` to Chatterbox `exaggeration`
- stitch turn WAVs with controlled pauses
- compare output quality against podcastfy compatibility mode

That should be a separate plan so transcript quality and audio backend migration stay independently testable.
