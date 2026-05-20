# Wiki Schema

## Domain
This wiki covers Hermes operations, deployment, and profile architecture, with the default profile currently focused on the `hermes-stack` repo and its surrounding runtime environment.

## Scope Boundaries
- Primary focus: `hermes-stack`, Hermes runtime/config, profile provisioning, shared SOUL instructions, Hindsight isolation, sync, and day-to-day VPS operations
- Secondary focus: adjacent Hermes implementation details only when they materially explain stack behavior or operational choices
- Out of scope by default: general AI research, unrelated repos, and speculative ideas not tied to active Hermes operations

## Conventions
- File names: lowercase, hyphens, no spaces (e.g., `profile-separation.md`)
- Every wiki page starts with YAML frontmatter
- Use `[[wikilinks]]` between wiki pages (minimum 2 outbound links per page)
- When updating a page, always bump the `updated` date
- Every new page must be added to `index.md` under the correct section
- Every action must be appended to `log.md`
- Keep this as one shared vault across Hermes profiles; express profile-specific behavior in page content and tags rather than separate wiki roots unless the user later requests hard wiki isolation
- For profile separation topics, distinguish carefully between shared instruction sources (`~/.hermes/shared/soul/...`) and isolated per-profile runtime state (workspace, config, Hindsight bank, sessions)

## Frontmatter
```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: entity | concept | comparison | query | summary
tags: [from taxonomy below]
sources: [raw/transcripts/source-name.md]
---
```

## Tag Taxonomy
- repo
- agent
- deployment
- operations
- profile
- multi-profile
- default-profile
- workspace
- config
- memory
- hindsight
- soul
- sync
- systemd
- docker
- documentation
- workflow
- automation
- troubleshooting

Rule: every tag on a page must appear in this taxonomy. Add new tags here before using them elsewhere.

## Page Thresholds
- Create a page when an entity/concept appears in 2+ sources OR is central to one source
- Add to an existing page when the source deepens something already covered
- Do not create a page for passing mentions or implementation trivia that is not operationally useful
- Split a page when it exceeds ~200 lines
- Archive a page when fully superseded; move it to `_archive/`, remove it from `index.md`, and update backlinks

## Entity Pages
One page per notable entity such as a repo, service, or major component. Include:
- What it is and why it matters
- Key facts, paths, and responsibilities
- Relationships to other entities and concepts via `[[wikilinks]]`
- Source references

## Concept Pages
One page per operational concept or recurring pattern. Include:
- Definition or explanation
- Current implementation state
- Tradeoffs, pitfalls, and open questions
- Related concepts and entities via `[[wikilinks]]`

## Comparison Pages
Use for side-by-side operational choices such as shared vs isolated components. Include:
- What is being compared and why
- Dimensions of comparison
- Recommendation or current verdict
- Sources

## Update Policy
When new information conflicts with existing content:
1. Check dates and prefer newer operational facts
2. If the conflict is real, note both positions with dates and sources
3. Mark the contradiction in frontmatter with `contradictions: [page-name]`
4. Flag it for user review in the next lint report
