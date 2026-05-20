# Current-state handoff notebooks

Use this pattern when the user wants NotebookLM to study a project state, not just ingest raw docs. It is especially useful for validation/research projects where NotebookLM must not infer that planned work has already happened.

## Trigger

- User asks for a NotebookLM notebook containing validation guides, implementation details, passes actually run, model/training status, or "what has actually been done".
- The source repo has many docs/reports and some are aspirational, planned, or scaffold-only.
- Target runner is the user's Mac, not the VPS.

## Pattern

1. Create a small explicit current-state handoff Markdown source first.
   - Put it under the project docs, e.g. `projects/<project>/docs/notebooklm/<topic>-current-state-YYYY-MM-DD.md`.
   - Start with a one-line state summary.
   - Separate sections: "What has actually been done", "Actual commands/passes run", "What has not been done yet", and "Compute/runtime reality".
   - Quote exact test/quality outputs when available.
   - State boundaries plainly: deterministic generator vs trained model, synthetic-only vs real holdout, pre-hardware vs hardware validated, report generated vs external expert reviewed.

2. Create a repo-relative source-list manifest.
   - Put the current-state handoff as the first source so NotebookLM anchors on it before reading detailed docs.
   - Include learning/validation guides, claims audit, reference-paper list, datasheets/model cards, generated reports, implementation files, and tests.
   - Keep paths repo-relative so the same manifest works on macOS and the VPS.

3. Create a Mac-portable wrapper script if one does not already exist.
   - Discover repo root from the script location.
   - Discover `nlm` through the generic helper or PATH, never hardcode `/home/hermes/...` for Mac users.
   - Provide `--print-sources` to verify that every manifest path exists before uploading.
   - Support optional title and `--profile PROFILE`.

4. Verify before handing off.
   - Run the script `--help` and `--print-sources`.
   - Run the project quality gate if the docs are checked by repo tests.
   - If documentation contains forbidden-claim scanners, avoid spelling forbidden phrases literally even as negative examples; rephrase the negative example.
   - Commit and push if the user expects to run the script from their Mac after `git pull`.

## Validated OpenJaw example

Commit `933bdb2` added:

- `scripts/create_openjaw_bruxsynth_validation_notebook.sh`
- `projects/openjaw/docs/notebooklm/bruxsynth-validation-source-list.txt`
- `projects/openjaw/docs/notebooklm/bruxsynth-current-state-2026-05-12.md`

The handoff explicitly said BruxSynth had a deterministic synthetic generator/evaluation reports, not trained learned model weights, real holdout validation, hardware validation, or expert-response validation. The wrapper used the generic `scripts/create_notebooklm_notebook.sh`, supported `--print-sources`, and was verified with full OpenJaw `make quality` before commit/push.
