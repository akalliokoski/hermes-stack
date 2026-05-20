# Beginner learning/evidence handoff pattern

Use this reference when an autoresearch loop produces ML/AI/EMG or other technical artifacts for a user who needs to understand and validate the work, not just receive status.

## Trigger

Apply when a scheduled/overnight pass, research campaign, or experiment loop produces any of:
- new metrics or evaluation results
- new reports/wiki pages
- a generator/evaluator/adapter distinction
- source papers/datasets the user must understand
- a next experiment contract
- user concern that the work is hard to understand, validate, or visually track

## Required morning/status handoff additions

After inspecting artifacts, include a beginner-readable section with:

1. **What actually happened**
   - list passes/jobs by purpose and result
   - distinguish code changes, report changes, wiki changes, and only-planned work
   - explicitly say when a generator/model/result does not exist yet

2. **Metric glossary tied to the exact run**
   - define each headline metric in one sentence and one concrete example from the artifact
   - include formulas for accuracy/recall/confusion when relevant
   - distinguish window-level, subject-level, split-level, and aggregate diagnostics

3. **Safe conclusion vs non-claim**
   - separate "safe to conclude" from "not safe to conclude"
   - preserve project claim boundaries, especially for synthetic-data, clinical, privacy, and hardware claims

4. **Evidence map**
   - list exact report/wiki/code/test paths
   - identify which artifacts are public-safe and which are local-only/redaction-sensitive

5. **Learning prerequisites**
   - list concepts the user should understand to validate the work
   - mark each as urgent/soon/later
   - link to project wiki concept pages when they exist

6. **Source/resource shelf**
   - list datasets, papers, URLs, docs, and why each matters
   - do not dump citations without explaining their role in the project

7. **Visual/progress surface**
   - if no dashboard/plot exists, state that plainly
   - recommend or create a static visual dashboard/diagram as the next artifact when visual tracking is a blocker

## Learning Evidence Graph pattern

For recurring technical campaigns, maintain a repo/wiki surface that links:

- Project -> Use case -> Experiment -> Metrics -> Artifacts -> Decisions -> Next steps
- Experiment -> Concepts required -> Sources/resources -> validation questions
- Claims -> supporting evidence and blocking non-claims

Prefer starting with static markdown/JSON/HTML artifacts before adding external services.

Suggested MVP files:
- `docs/learning/<experiment>-founder-digest.md`
- `docs/learning/evidence-registry.json`
- `wiki/concepts/<concept>.md`
- `wiki/assets/<project>-learning-evidence-dashboard.html`

## Tooling guidance

Use external tools only when the static repo surface is insufficient:
- MLflow/W&B: repeated model-run tracking and comparison
- Evidently/model cards: visual data/model report exports
- Obsidian/Juggl/Excalibrain-style graph views: concept/prerequisite browsing
- ExperimentOps-style decision logs: hypothesis, target metric, result, decision, next step

## Pitfalls

- Do not answer only with a technical status summary when the user asked to understand/validate the work.
- Do not treat markdown tables as a visual dashboard if the user asked for visual progress tracking.
- Do not claim a planned platform file was created unless a write tool succeeded.
- Do not mix "what was done" with "what should be done next"; keep them separate.
- Do not assume the user knows ML/EMG terminology; define terms from basics and tie definitions to the current artifact.