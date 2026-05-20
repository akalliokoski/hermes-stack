# Shared Skill Smoke Test Brief

Captured: 2026-04-21
Type: generated brief
Purpose: Archive explainer briefs in the shared wiki so they are easy to find and reuse.

## Provenance
- Pipeline: `video-explainer-pipeline`
- Title: `Shared Skill Smoke Test`

## Content
# Overview

A concise NotebookLM-style explainer about a very small but important event: the shared video skill is present, readable, and ready to guide a production workflow. Rather than treating this as a generic “it loaded” success message, the video frames skill loading as the first proof that the explainer pipeline has the right operating context before any real source ingestion, briefing, or rendering begins.

The story stays intentionally narrow. It does not claim a full render happened. It only shows the stronger, source-grounded conclusion available from the prompt context: the session has the shared video explainer skill available, and that skill defines a structured workflow for turning source material into infographic-style explainer outputs.

# Audience

- Hermes operators validating shared-profile setup
- Builders testing skill availability before a real production run
- Anyone who wants a quick, visual explanation of why “the skill loaded” matters operationally

# Core Takeaway

The smoke test passes when the shared video explainer skill is present in-session, because that confirms Hermes has the workflow context needed to generate a structured brief, scene plan, visual language, and downstream build notes for infographic-style explainer production.

# Source Notes

- No local files were provided.
- No URLs were provided.
- This brief is grounded only in:
  - the user prompt
  - the active shared `video-explainer-pipeline` skill loaded in the current session
  - the related `baoyu-infographic` skill loaded for scene and slide craft guidance
- Because no external source material was supplied, the video should avoid claims about runtime success, file outputs, or rendered media. It should stay focused on verified in-session skill availability and the workflow it defines.

# Narrative Arc

Start with the smallest possible test: can Hermes see the shared video skill at all? Then widen the frame. Show that this is not just a UI detail or a cosmetic label; it is the loading of a production pattern. The middle beats explain what that pattern unlocks: structured briefs, scene plans, infographic-first visuals, optional narration, and delivery-oriented build notes. The ending lands on the practical meaning of the smoke test: before real content arrives, the workflow context is already in place.

# Scene Plan

## Scene 1 — `s1_smoke_test_prompt`
Goal: Establish the test condition and frame the question clearly.

On-screen visuals:
- Hero: `Smoke Test` card
- Supporting nodes: `Shared Skill`, `Current Session`, `Question: Did it load?`
- Flow: `Prompt -> Session`

Narration beats:
- Open on a simple premise: this is not a full production run.
- It is a smoke test for one thing only: whether the shared video skill loads.
- Set expectation that the answer must stay grounded in what the session actually provides.

## Scene 2 — `s2_skill_detected`
Goal: Show the verified result: the video explainer skill is available in-session.

On-screen visuals:
- Hero: `video-explainer-pipeline`
- Supporting nodes: `Loaded`, `Readable`, `Active Guidance`
- Flow: `Shared skill -> Current session -> Ready context`

Narration beats:
- Confirm that the shared video explainer skill is present in the session.
- Emphasize that this matters because the skill is not just a label; it carries workflow instructions.
- Keep the claim narrow: available and usable, not yet executed end-to-end.

## Scene 3 — `s3_what_loading_means`
Goal: Translate “skill loaded” into operational meaning.

On-screen visuals:
- Hero: `Workflow Context`
- Supporting nodes: `Brief`, `Scene Plan`, `Build Notes`
- Containment: `Workflow Context contains Brief / Scene Plan / Build Notes`

Narration beats:
- Explain that loading the skill gives Hermes a playbook for how to structure the explainer.
- The playbook includes the brief itself, a narrative arc, scene planning, and practical build guidance.
- This is why the smoke test is meaningful: context arrives before production.

## Scene 4 — `s4_infographic_first`
Goal: Clarify the intended visual style and why it fits this test.

On-screen visuals:
- Hero: `Infographic Slides`
- Supporting nodes: `Scene Cards`, `Short Labels`, `Node-and-arrow diagrams`
- Flow: `NotebookLM pacing -> Infographic scenes`

Narration beats:
- Note that the style target is conversational pacing, but the visuals are infographic-first.
- The goal is scene cards, diagrams, and compact slide logic rather than dense paragraphs.
- This keeps the video legible even when the subject is workflow and tooling.

## Scene 5 — `s5_related_skill_support`
Goal: Show that the visual craft side is also supported by a related skill.

On-screen visuals:
- Hero: `baoyu-infographic`
- Supporting nodes: `Layout thinking`, `Visual motifs`, `High-density simplification`
- Flow: `Related skill -> Better slide craft`

Narration beats:
- Introduce the related infographic skill as the source of visual discipline.
- It reinforces short labels, clear layout choices, and simplified high-density diagrams.
- So the smoke test is stronger than “a skill exists”; it shows the explainer has both workflow guidance and visual guidance.

## Scene 6 — `s6_no_external_sources`
Goal: Be explicit about scope and source limits.

On-screen visuals:
- Hero: `Source Boundary`
- Supporting nodes: `No local files`, `No URLs`, `Prompt-only grounding`
- Left-to-right flow: `No files -> No URLs -> Narrow claims`

Narration beats:
- State clearly that no local files or external URLs were supplied.
- Because of that, the brief should not pretend to summarize outside material.
- The only defensible story is the one grounded in the prompt and loaded skills.

## Scene 7 — `s7_production_readiness`
Goal: Land the practical takeaway for operators.

On-screen visuals:
- Hero: `Ready for Real Input`
- Supporting nodes: `Ingest sources`, `Generate brief`, `Build scenes`
- Flow: `Skill loaded -> Sources later -> Production path`

Narration beats:
- End on the operational meaning of the result.
- The smoke test says the shared skill architecture is working well enough to guide the next real job.
- Once actual files or URLs are added, Hermes can move from validation into structured explainer production.

# Visual Language

- Palette:
  - Background: soft charcoal or deep slate
  - Primary: electric cyan
  - Secondary: warm off-white
  - Accent: mint or lime for “pass/ready” states
  - Warning/scope note: muted amber
- Typography:
  - Headings: bold geometric sans
  - Labels: clean sans, medium weight
  - Code/skill names: monospace treatment
  - Keep text blocks short; prefer label clusters over paragraphs
- Pacing:
  - Calm, confident, conversational
  - 1 clear idea per scene
  - Slight hold after each scene reveal so the viewer can read the node relationships
- Reusable visual motifs:
  - rounded skill cards
  - session boundary frames
  - node-and-arrow workflow diagrams
  - containment boxes for “workflow context”
  - green check state for validated facts
  - amber boundary tag for “no sources provided”
- Layout bias:
  - Prefer hub-and-spoke or left-to-right process diagrams
  - For dense scenes, collapse into 1 hero object plus 2 to 3 support nodes
  - Avoid long bullet stacks; convert to labeled modules

# Optional Narration Draft

## `s1_smoke_test_prompt`
This explainer starts with a tiny question: can Hermes actually see the shared video skill in this session? Not whether a full video rendered. Not whether media was published. Just whether the right production guidance is present.

## `s2_skill_detected`
The answer, from the current session context, is yes. The shared `video-explainer-pipeline` skill is loaded and available as active guidance. That means Hermes is not improvising from scratch; it has a defined workflow to follow.

## `s3_what_loading_means`
And that matters because a loaded skill is really loaded structure. It tells Hermes how to shape a brief, how to define a narrative arc, how to break the story into scenes, and how to think about downstream build steps.

## `s4_infographic_first`
Just as important, the target format here is not a wall of text. The pacing can feel conversational and NotebookLM-inspired, but the visuals should resolve into infographic slides, scene cards, and compact diagrams that read quickly.

## `s5_related_skill_support`
There is also visual craft support in the session through the infographic skill. That gives the workflow a second layer: not just what to build, but how to make the scenes clearer, denser, and more legible.

## `s6_no_external_sources`
There is one important limit. No local files were provided, and no URLs were provided. So this brief should stay disciplined. It can verify skill presence and describe the workflow that skill defines, but it should not invent outside facts or pretend a full source package exists.

## `s7_production_readiness`
That is the real outcome of the smoke test. The shared skill loads, the workflow context is in place, and Hermes is ready for the next step. As soon as real source material arrives, the system can move from validation into actual explainer production.

# Build Notes

- Treat this as a silent visual explainer by default.
- Generate infographic-style slides or scene cards, not animation-heavy sequences.
- Use one scene per card or per compact diagram.
- Keep each scene built around:
  - 1 hero object
  - 2 to 3 supporting nodes
  - explicit arrows, containment, or left-to-right progression
- Prefer these visual constructions:
  - Scene 1: prompt card feeding into a session frame
  - Scene 2: skill card with green “loaded” badge
  - Scene 3: containment box labeled `Workflow Context`
  - Scene 4: visual-style comparison collapsed into one infographic-first lane
  - Scene 5: supporting skill card chained into the visual system
  - Scene 6: source boundary warning panel
  - Scene 7: readiness path from validation to future production
- Pause moments:
  - After Scene 2 reveal, pause briefly so the validated result lands
  - After Scene 3, pause to let the workflow components read clearly
  - After Scene 6, give a deliberate scope pause so the “no sources” boundary is understood
  - End Scene 7 with a slightly longer hold on the readiness diagram
- Keep on-screen text minimal:
  - short labels
  - short captions
  - no paragraph blocks as primary visual content
- If converted into a manifest later:
  - mark Scene 2 and Scene 7 as emphasis beats
  - mark Scene 6 as a scope-check beat
  - reserve extra hold time for diagrams with containment and arrows
- Good default build direction:
  - dark background
  - high-contrast labels
  - cyan arrows
  - green validation accents
  - monospace for skill names and technical labels
