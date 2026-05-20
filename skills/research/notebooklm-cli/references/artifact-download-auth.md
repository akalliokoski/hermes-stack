# NotebookLM artifact download auth on the Hermes VPS

Validated findings from the April-May 2026 NotebookLM sessions.

## Symptom

Notebook and source operations succeed, `nlm login --check` passes, and artifact creation can complete, but local artifact download still fails.

Validated failure variants:
- audio generation completes, but `nlm download audio ...` fails after a redirect to Google login
- slide-deck generation completes, but `nlm download slide-deck ...` fails on the final hosted-file fetch with `403 Forbidden`
- report generation may still download successfully in the same session, so artifact readiness is not the same as artifact retrievability

Observed surfaced error chains:
- audio: `ClientAuthenticationError: Download failed: Redirected to login page. Run 'nlm login' to refresh credentials.`
- slide deck: final GET to Google artifact hosting can return `403 Forbidden` even after the deck is marked `completed`

## What this means

The NotebookLM API/session used for notebook CRUD and artifact status polling can still be valid while the final binary artifact URL is not downloadable from the VPS session.

In other words:
- notebook access working does not guarantee artifact download access
- `completed` in `nlm studio status` does not guarantee the file can be fetched locally
- different artifact types can behave differently in the same session (for example, report download succeeds while audio and slide deck fail)

## Reproduction that proved the distinction

Successful steps from the bruxism-cap deep-dive session:
- `nlm login --manual --file /home/hermes/.nlm/cookies.txt --force`
- `nlm login --check`
- `nlm notebook create "bruxism-cap deep dive (2026-05-05)"`
- `nlm source add <notebook-id> --file ... --wait`
- `nlm audio create <notebook-id> ... --confirm`
- `nlm slides create <notebook-id> ... --confirm`
- `nlm report create <notebook-id> ... --confirm`
- `nlm studio status <notebook-id>` later showed all three artifacts as `completed`
- `nlm download report <notebook-id> --id <report-id> --output ...` succeeded

Failure steps:
- `nlm download audio <notebook-id> --id <audio-id> --output ... --no-progress`
- `nlm download slide-deck <notebook-id> --id <slide-id> --output ...`

Package-level inspection showed:
- audio ultimately redirected through `lh3.googleusercontent.com` / `lh3.google.com` to Google login
- slide deck ultimately fetched from `contribution.usercontent.google.com` and returned `403 Forbidden`

## Practical operator guidance

1. After generating artifacts, always verify both:
   - `nlm studio status <notebook-id>`
   - an actual `nlm download ...` to a local file path for every artifact the user cares about
2. Do not declare success based only on artifact status inside NotebookLM.
3. If audio or slide download fails, refresh the cookie export from a currently working NotebookLM browser session and re-run manual login import.
4. Prefer exporting cookies from a session that has recently opened the notebook and accessed artifact-related UI, not just a stale background Google session.
5. If the issue persists after a fresh cookie import, treat it as a hosted-artifact cookie/scope mismatch rather than an artifact-readiness problem.
6. Preserve the notebook URL plus artifact IDs in a local run-summary file so the user can retrieve completed artifacts manually in the NotebookLM web UI.
7. If one artifact type downloads successfully and another does not, record that asymmetry explicitly; it is useful diagnostic evidence.

## Useful local paths from validated sessions

- Shared auth store: `/home/hermes/.notebooklm-mcp-cli/profiles/default`
- Manual cookie file used for import: `/home/hermes/.nlm/cookies.txt`
- Earlier test notebook output directory: `/home/hermes/work/hermes-stack/tmp/notebooklm/`
- Bruxism-cap output directory: `/home/hermes/work/ai-lab/projects/bruxism-cap/artifacts/notebooklm/`
- Example run summary: `/home/hermes/work/ai-lab/projects/bruxism-cap/artifacts/notebooklm/notebooklm-run-summary-2026-05-05.md`

## Example commands

```bash
nlm login --check
nlm studio status <notebook-id>
nlm download report <notebook-id> --id <report-id> --output /tmp/report.md
nlm download audio <notebook-id> --id <audio-id> --output /tmp/audio.m4a --no-progress
nlm download slide-deck <notebook-id> --id <slide-id> --output /tmp/slides.pdf
```

## Recommended handoff when downloads stay blocked

When the notebook and artifacts are real but local download remains blocked:
- give the user the NotebookLM notebook URL
- give the artifact IDs
- state exactly which artifacts are completed in NotebookLM
- state exactly which ones were downloaded locally and which were blocked
- point the user to the NotebookLM web UI for manual retrieval of completed artifacts
