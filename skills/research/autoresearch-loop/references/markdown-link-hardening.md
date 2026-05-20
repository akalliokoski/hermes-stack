# Markdown link hardening in autoresearch loops

Use this when an autoresearch pass is editing reviewer-facing markdown links across a repo.

## Why this reference exists

A session on OpenJaw showed that bulk conversion from plain/backticked file paths to clickable markdown links can look correct in diff form while still producing broken relative targets. Regex scans alone were not sufficient. A follow-up filesystem link-resolution audit found 21 broken links across changed docs even though the rewrite initially appeared successful.

## Safe pass shape

1. Inspect the current handoff and the exact changed docs first.
2. Make one bounded link-hardening increment.
3. Run `git diff --check` on the touched doc set.
4. Run a filesystem link-resolution audit over the changed markdown files.
5. Fix only true broken local links whose targets exist.
6. Leave planned-but-nonexistent artifacts, wildcard examples, frontmatter `evidence_paths`, command snippets, and local-only absolute evidence paths as plain text when appropriate.
7. If the queued doc is already clean, treat that as a valid verification pass: record that no reviewer-facing body edits were needed, preserve any intentional plain-text exceptions, and advance the next exact doc instead of forcing cosmetic churn.
8. Update the handoff with exact files audited, exceptions left intentionally plain, and the next exact doc to inspect.

## Link-resolution audit pattern

Do not trust markdown appearance alone. Resolve each local markdown target against the source file's directory and check `exists()` on disk.

Minimal Python pattern:

```python
import pathlib, re
link_re = re.compile(r'\[[^\]]+\]\(([^)]+)\)')
for md in changed_markdown_files:
    text = md.read_text()
    for line_no, line in enumerate(text.splitlines(), start=1):
        for m in link_re.finditer(line):
            target = m.group(1).strip()
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            resolved = (md.parent / target).resolve()
            if not resolved.exists():
                print(md, line_no, target)
```

## Commit/push gate when cron is involved

If the repo already has an overlapping repo-mutating autoresearch cron loop:
- pause that cron job before manual review, staging, commit, or push
- perform the review/commit/push window manually
- resume or replace the loop only after the workspace is stable again

This avoids racing edits, stale handoffs, and false confidence from a passing diff on files that another pass may mutate mid-review.

## Session-specific OpenJaw examples captured from this pattern

Broken-relative-link classes that were found and fixed:
- `projects/openjaw/docs/evaluation/...` links used from files already inside `docs/evaluation/`; same-dir `./...` was required.
- `docs/...` links used from files under `docs/operations/`; `../...` or `./...` was required depending on target.
- links into `wiki/` from `docs/learning/_cockpit/` and `docs/learning/` were one `..` short.
- `control-requests/README.md` from an operations doc needed to point at `../learning/_cockpit/control-requests/README.md`.

Examples of intentional non-fixes:
- a placeholder reference to `docs/learning/openjaw-learning-map.md` when the target file did not exist
- frontmatter path inventories such as `evidence_paths`
- absolute local-only artifact paths kept as evidence strings rather than reviewer-facing clickable links

## Practical rule

For markdown-hardening autoresearch, the pass is not done when the markdown looks cleaner. The pass is done only when:
- diff formatting is clean,
- local targets resolve on disk,
- intentional placeholders remain plain,
- and the handoff records what was verified and what remains.