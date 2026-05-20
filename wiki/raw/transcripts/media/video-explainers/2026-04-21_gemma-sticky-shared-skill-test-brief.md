# Gemma Sticky Shared Skill Test Brief

Captured: 2026-04-21
Type: generated brief
Purpose: Archive explainer briefs in the shared wiki so they are easy to find and reuse.

## Provenance
- Pipeline: `video-explainer-pipeline`
- Title: `Gemma Sticky Shared Skill Test`

## Content
# Overview

This explainer verifies a simple but important plumbing fact: in the `gemma` profile, the shared `video-explainer-pipeline` skill is available in-session and can shape the workflow for NotebookLM-style explainer videos. The clearest narrative thread is not “how every skill works,” but “how one shared skill becomes usable inside a specific profile.”

The visual story should move from proof of context, to proof of wiring, to proof of discovery, to proof of practical effect. The result should feel like a confident system walkthrough rather than a debugging log.

# Audience

- Hermes operators validating profile behavior
- Builders maintaining shared-vs-profile skill architecture
- Anyone checking whether `gemma` can access shared video workflow guidance without duplicating local skill files

# Core Takeaway

`gemma` can load the shared `video-explainer-pipeline` skill because its profile config includes `/home/hermes/.hermes/shared/skills` in `skills.external_dirs`, and the skill is discoverable in the media skill list and readable from the shared skill path.

# Source Notes

Primary local sources inspected with Hermes tools:

- `/home/hermes/.hermes/profiles/gemma/config.yaml`
  - `skills.external_dirs` includes `/home/hermes/.hermes/shared/skills`
- `/home/hermes/.hermes/shared/skills/media/video-explainer-pipeline/SKILL.md`
  - defines the shared `video-explainer-pipeline` skill
  - states the workflow is for NotebookLM-style explainer videos
  - states default mode is silent visual output unless audio is explicitly requested
- Hermes skill discovery output for media skills
  - includes `video-explainer-pipeline` in the available media skills for this profile
- `/home/hermes/.hermes/profiles/gemma/skills/autonomous-ai-agents/hermes-skill-scope-debugging/SKILL.md`
  - distinguishes profile-local skills from truly shared skills
  - states `~/.hermes/shared/skills/...` is the shared scope

Constraints from the source set:

- No user-provided local files
- No user-provided URLs
- Claims in this brief should stay limited to profile wiring, shared skill presence, and the video workflow described inside the shared skill itself

# Narrative Arc

Start with the question: “Did the shared video skill actually load inside gemma?” Then answer it in three clean moves.

First, establish the scope model: some skills are profile-local, others are truly shared. Next, show the wiring that matters: the `gemma` profile explicitly points at the shared skills directory. Then show the operational proof: `video-explainer-pipeline` appears in the available media skills and its shared `SKILL.md` is present and readable.

Finish by translating that proof into user value: because the skill loads, `gemma` inherits the same structured explainer-video workflow, including infographic-first scenes, silent-by-default output, and Jellyfin-oriented delivery assumptions.

# Scene Plan

## Scene s01 — The verification question
- Goal: Frame the test as a focused yes/no systems check
- On-screen visuals:
  - Hero: terminal card `Gemma Sticky Shared Skill Test`
  - Node: `gemma profile`
  - Node: `shared video skill`
  - Arrow: `can it load?`
- Narration beats:
  - Open on one concrete question, not a broad architecture lecture
  - This is a verification pass for one shared skill inside one profile
  - The test target is `video-explainer-pipeline`

## Scene s02 — Shared vs local scope
- Goal: Explain why the question matters at all
- On-screen visuals:
  - Hero: three-tier scope diagram
  - Node: `~/.hermes/skills`
  - Node: `~/.hermes/profiles/<name>/skills`
  - Node: `~/.hermes/shared/skills`
  - Left-to-right flow: `default local -> profile local -> shared`
- Narration beats:
  - Hermes skill resolution is scope-sensitive
  - The debugging skill explicitly separates default local, profile-local, and shared skill trees
  - So the real question becomes: is `gemma` wired to the shared tree?

## Scene s03 — The gemma wiring proof
- Goal: Show the exact config fact that enables shared skill loading
- On-screen visuals:
  - Hero: config file panel `config.yaml`
  - Highlight: `skills.external_dirs`
  - Node: `/home/hermes/.hermes/shared/skills`
  - Arrow: `gemma -> shared skills`
- Narration beats:
  - In `gemma`’s profile config, `skills.external_dirs` includes the shared skills path
  - That is the mechanical link that exposes cross-profile skills to this profile
  - This is the strongest configuration-level proof in the source set
  - Pause after the highlighted path lands on screen

## Scene s04 — Discovery inside the running profile
- Goal: Show that the skill is not just on disk, but discoverable to the profile
- On-screen visuals:
  - Hero: media skill list
  - Highlight chip: `video-explainer-pipeline`
  - Node: `podcast-pipeline`
  - Node: `youtube-content`
  - Containment: `media skills`
- Narration beats:
  - The available media skills for this profile include `video-explainer-pipeline`
  - That moves the claim from configuration theory to in-profile discovery
  - The skill is showing up alongside the other media tools, exactly where it should

## Scene s05 — The shared skill itself
- Goal: Confirm the loaded skill is the shared video workflow definition
- On-screen visuals:
  - Hero: `video-explainer-pipeline/SKILL.md`
  - Node: `NotebookLM-style explainers`
  - Node: `infographic slides/scenes`
  - Node: `silent by default`
  - Arrow chain: `skill file -> workflow rules -> output behavior`
- Narration beats:
  - The shared `SKILL.md` defines the actual workflow
  - It specifies NotebookLM-style pacing, infographic-style slides and scene cards, and a silent-first default
  - So loading the skill is not abstract; it imports concrete production guidance

## Scene s06 — What the verification means
- Goal: Land the conclusion and practical implication
- On-screen visuals:
  - Hero: status badge `Verified`
  - Node: `gemma config`
  - Node: `shared skill path`
  - Node: `media skill discovery`
  - Converging arrows into: `usable shared video workflow`
- Narration beats:
  - The verification succeeds on three levels: scope model, config wiring, and skill discovery
  - `gemma` can access the shared `video-explainer-pipeline` skill
  - That means future explainer-video work can rely on the shared workflow without duplicating a profile-local copy
  - Brief closing pause for emphasis

# Visual Language

Palette:
- Background: deep charcoal `#0F172A`
- Primary accent: Gemma blue `#60A5FA`
- Secondary accent: mint `#34D399`
- Highlight/warning accent: amber `#FBBF24`
- Neutral panels: slate `#1E293B` and `#334155`
- Text: off-white `#E5EEF8`

Typography:
- Headings: bold geometric sans, large, high contrast
- Labels: medium sans, short noun phrases
- Code/path text: mono style treatment for file paths, skill names, and config keys
- Keep line length short; prefer labels over paragraphs on screen

Pacing:
- NotebookLM-inspired but visual-first
- Calm, confident reveals
- One major idea per scene
- Let highlighted config lines and path strings sit long enough to read
- Use short pauses after the key proof moments in scenes s03, s04, and s06

Reusable visual motifs:
- Terminal cards for test framing
- File panels for source proof
- Highlight chips for skill names
- Node-arrow diagrams for scope and dependency relationships
- Containment boxes for “media skills” and “shared skills”
- Left-to-right proof flow: `scope -> wiring -> discovery -> conclusion`

# Optional Narration Draft

If narration is later desired, keep it concise and leave breathing room between proof steps.

Scene s01:
“We’re checking one very specific thing: does the shared video explainer skill actually load inside the gemma profile? If it does, the rest of the video workflow can stay shared instead of being copied profile by profile.”

Scene s02:
“The key background is that Hermes skills live in different scopes. Some are default-profile local, some are profile-local, and some are truly shared. So this test is really about whether gemma can see the shared scope.”

Scene s03:
“The strongest wiring proof sits right in gemma’s config. Under `skills.external_dirs`, the profile includes `/home/hermes/.hermes/shared/skills`. That path is what makes shared skills available here.”

Scene s04:
“And it’s not just a path on disk. In the media skill list for this profile, `video-explainer-pipeline` shows up as an available skill. That’s the operational signal that discovery is working.”

Scene s05:
“When we inspect the shared skill file itself, we see the workflow it brings in: NotebookLM-style explainers, infographic-style slides and scene cards, and a silent-by-default production model unless audio is explicitly requested.”

Scene s06:
“So the conclusion is straightforward. Gemma is wired to shared skills, the shared video skill is discoverable, and the profile can use that common video workflow directly. The test passes.”

# Build Notes

- Build this as infographic-style slide cards, not dense prose slides.
- Prefer a `linear-progression` or compact `hub-spoke` slide logic across the full piece:
  - `question -> scope -> config -> discovery -> workflow -> verified`
- Each scene should use one hero object plus 2 to 3 supporting nodes.
- Use explicit arrows for causality:
  - `gemma config -> shared path`
  - `shared path -> skill discovery`
  - `skill discovery -> usable workflow`
- Keep on-screen text short:
  - file paths
  - config keys
  - skill names
  - outcome badges
- For high-density material, use compact diagrams instead of stacked bullets.
- Good pause points:
  - after the scope diagram in s02
  - after the highlighted `external_dirs` path in s03
  - after the skill-list highlight in s04
  - after the final `Verified` convergence in s06
- If rendering as silent slides, increase hold time on s03 and s04 because those scenes carry the proof.
- If adding narration later, keep captions derived from the same scene structure and avoid placing full narration paragraphs on-screen.
- Recommended final artifact structure for slide generation:
  - one scene card per `scene id`
  - one visual motif per card
  - reusable highlight styling for paths, config keys, and skill names
