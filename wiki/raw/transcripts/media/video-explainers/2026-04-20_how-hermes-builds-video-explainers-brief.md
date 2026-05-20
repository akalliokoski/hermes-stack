# How Hermes Builds Video Explainers Brief

Captured: 2026-04-20
Type: generated brief
Purpose: Archive explainer briefs in the shared wiki so they are easy to find and reuse.

## Provenance
- Pipeline: `video-explainer-pipeline`
- Title: `How Hermes Builds Video Explainers`

## Content
# Overview

This explainer follows one simple thread: Hermes turns source material into a finished video by moving through four concrete stages — brief, scaffold, render runtime, and delivery. The story is not “Hermes makes videos magically.” It is that Hermes uses a repo-backed, repeatable workflow to generate a structured brief, scaffold a Manim project, prepare a local rendering environment, and place the result in a Jellyfin-served library.

The tone should feel like NotebookLM at its best: calm, clear, and conversational. But visually, the piece should be designed for Manim execution first. That means every idea appears as a clean transformation of the previous one, with deliberate pauses after each major reveal.

# Audience

This video is for:
- technically curious users who want to understand Hermes’ video explainer workflow without reading shell scripts
- operators working in `hermes-stack` who need the mental model behind the pipeline
- builders who know what Manim, Jellyfin, or a venv are at a high level, but do not yet know how Hermes connects them

Assumed knowledge:
- basic familiarity with scripts, files, and rendered video output
- no need to know Manim internals in advance

# Core Takeaway

Hermes builds video explainers through a repo-defined, visual-first pipeline: it generates a structured brief from sources, scaffolds a Manim project in Jellyfin-backed storage, relies on a local Manim venv prepared by deploy/bootstrap scripts, and treats narration as optional rather than required.

# Source Notes

- `video-explainer-pipeline/SKILL.md`
  - Defines the intended architecture: Hermes extracts and normalizes sources, generates a structured brief, Manim turns that brief into scene classes and renders, output lives under `/data/jellyfin/videos/ai-generated/`, Jellyfin serves it over Tailscale, and the brief is archived in the shared wiki.
  - States that the default mode is no audio, with narration or soundtrack as an explicit later opt-in.
  - Names `/opt/hermes/scripts/make-manim-video.py` as the canonical helper and describes its outputs: project directory, `brief.md`, archived wiki brief, `source-packet.md`, `script.py`, and `render.sh`.
  - Emphasizes local Manim on the VPS as the preferred runtime, not Docker.
  - Notes operational pitfalls: scaffold does not equal finished film, render low quality first, keep deliverables under `/data/jellyfin/videos`, and avoid leaving raw Manim artifacts in the served library tree.

- `scripts/setup-video-pipeline.sh`
  - Creates or repairs the dedicated venv at `VIDEO_PIPELINE_VENV` or `/home/hermes/.venvs/video-pipeline`.
  - Ensures Python exists, runs `ensurepip`, upgrades `pip`, `setuptools`, and `wheel`, installs `manim==0.20.1`, verifies Python modules `manim` and `cairo`, and checks `manim --version`.
  - Emits the resolved Python and Manim binary paths for downstream use.

- `scripts/make-manim-video.py`
  - Loads defaults such as `VIDEO_OUTPUT_DIR=/data/jellyfin/videos/ai-generated`, `VIDEO_SERIES=notebooklm-style-explainers`, and `VIDEO_PIPELINE_VENV=/home/hermes/.venvs/video-pipeline`.
  - Builds a strict prompt for Hermes to generate a markdown brief with the exact sections requested here.
  - Calls Hermes chat with the `manim-video` skill to generate `brief.md` unless a brief is supplied or brief generation is skipped.
  - Creates a dated project directory, writes `brief.md`, `source-packet.md`, `script.py`, `render.sh`, and `plan.md`, and archives the generated brief into the shared wiki under the video explainers area.
  - The render helper defaults to `Scene1_Introduction`, uses the local Manim binary from the video venv, and warns the operator to bootstrap the local pipeline first if Manim is missing.
  - Marks audio as optional later; silent video remains the default.

- `scripts/remote-deploy.sh`
  - Creates the needed host directories for Jellyfin-backed video storage, including `/data/jellyfin/videos/ai-generated`.
  - Installs the Ubuntu system packages required for the video runtime: `build-essential`, `python3-dev`, `pkg-config`, `libcairo2-dev`, `libpango1.0-dev`, and `ffmpeg`.
  - Runs `scripts/setup-video-pipeline.sh` during deploy, so the local video rendering environment is part of the standard repo deployment path rather than a one-off manual setup.

# Narrative Arc

Use a build-up arc with a clean operational reveal.

1. Start with the user request: “Make me an explainer.”
2. Show that Hermes does not jump to rendering; it first turns raw sources into a structured brief.
3. Reveal that the brief becomes a scaffolded project, not just prose.
4. Show the local runtime layer: a dedicated Manim venv and system packages make rendering reliable.
5. End with the delivery layer: the final video lives in Jellyfin-backed storage and the brief is archived in the wiki.

The “aha” moment is that the pipeline is not one monolithic script. It is a sequence of grounded handoffs:
source material -> brief -> project scaffold -> local render environment -> delivered video.

# Scene Plan

## Scene `S1_request_to_pipeline`
- Goal: Introduce the user-facing promise and frame the workflow as a sequence rather than a black box.
- On-screen visuals:
  - A single prompt card: “How Hermes Builds Video Explainers”
  - Below it, four dim placeholders that will later light up: Brief, Scaffold, Render, Deliver
  - Subtle arrow line connecting them left to right
- Narration beats:
  - “At first glance, this sounds like one request: make a video.”
  - “But Hermes handles it as a pipeline.”
  - “First the brief, then the project scaffold, then the render environment, and finally delivery.”

## Scene `S2_sources_become_brief`
- Goal: Show that Hermes starts by reading provided inputs and generating a structured explainer brief.
- On-screen visuals:
  - A stack of source cards labeled with the local file names
  - Those cards condense into a single `brief.md` document
  - Highlighted section headers appearing one by one: Overview, Audience, Core Takeaway, Scene Plan
- Narration beats:
  - “The first job is source digestion.”
  - “The helper script builds a strict prompt, asks Hermes to read the supplied local files, and requires a structured markdown brief.”
  - “That brief is not filler. It defines the narrative arc, scene beats, visual language, and build notes.”

## Scene `S3_brief_becomes_project`
- Goal: Make the scaffold step feel tangible and concrete.
- On-screen visuals:
  - `brief.md` slides into a project folder
  - Folder opens into labeled files orbiting around it:
    - `brief.md`
    - `source-packet.md`
    - `script.py`
    - `render.sh`
    - `plan.md`
  - Path label under the folder: `/data/jellyfin/videos/ai-generated/<series>/<date_slug>/`
- Narration beats:
  - “Next, Hermes does not start from scratch each time.”
  - “`make-manim-video.py` creates a dated project directory in Jellyfin-backed storage.”
  - “It writes the brief, records the source packet, creates a starter Manim script, writes a render helper, and stores a plan for implementation.”

## Scene `S4_visual_first_not_audio_first`
- Goal: Clarify the pipeline’s design philosophy: visual explainer first, audio optional.
- On-screen visuals:
  - Split frame
  - Left: a bright animated geometry panel labeled “Visual-first”
  - Right: a muted waveform panel labeled “Optional later”
  - Audio toggle starts off, then pulses softly without turning on
- Narration beats:
  - “One important policy shapes the whole workflow.”
  - “These videos are silent by default.”
  - “Narration can be added later, but the pipeline is designed so the visuals stand on their own.”

## Scene `S5_local_runtime_layer`
- Goal: Explain how the render environment is prepared and why local Manim matters.
- On-screen visuals:
  - A venv capsule labeled `/home/hermes/.venvs/video-pipeline`
  - Dependency badges flow into it: `pip`, `setuptools`, `wheel`, `manim==0.20.1`, `cairo`
  - Underneath, a second row of system package tiles: `build-essential`, `python3-dev`, `pkg-config`, `libcairo2-dev`, `libpango1.0-dev`, `ffmpeg`
- Narration beats:
  - “Rendering depends on a dedicated local runtime.”
  - “`setup-video-pipeline.sh` repairs or creates the venv, ensures pip exists, installs Manim 0.20.1, and verifies both `manim` and `cairo`.”
  - “And `remote-deploy.sh` installs the required Ubuntu packages first, so the render path is part of normal repo deployment.”

## Scene `S6_render_helper_to_mp4`
- Goal: Connect the scaffold to actual rendering behavior without getting lost in implementation detail.
- On-screen visuals:
  - `render.sh` appears as a command card
  - It points to `MANIM_BIN` inside the video venv
  - A draft render bar runs at `-ql`, then a polished output tile appears as `final.mp4`
  - Small side note: “Draft first, final later”
- Narration beats:
  - “The scaffold includes a render helper that looks for the local Manim binary in the video venv.”
  - “It starts from scene-based rendering, with a default introduction scene already scaffolded.”
  - “The intended rhythm is draft first at low quality, then final render once the scenes are right.”

## Scene `S7_archive_and_delivery`
- Goal: Land the full system picture: archive, storage, and serving.
- On-screen visuals:
  - Final MP4 moves into a clean delivery folder under `/data/jellyfin/videos/ai-generated/`
  - A parallel copy of the brief moves into `/home/hermes/sync/wiki/raw/transcripts/media/video-explainers/`
  - Jellyfin icon lights up at the end
  - The original four-step pipeline from Scene 1 returns, now fully illuminated
- Narration beats:
  - “The end state is operational, not just artistic.”
  - “The video lives in Jellyfin-backed storage so it can be served from the media library.”
  - “And the brief is archived into the shared wiki, so the reasoning behind the video stays reusable.”
  - “That is how Hermes builds explainers: grounded sources, a structured brief, a repeatable Manim scaffold, a verified local runtime, and clean delivery.”

# Visual Language

- Palette
  - Background: `#1C1C1C`
  - Primary pipeline color: `#58C4DD` for active workflow elements like briefs, paths, and arrows
  - Secondary structure color: `#83C167` for successful artifacts like project folders and final outputs
  - Accent: `#FFFF00` for the “aha” moments, especially the visual-first policy and the final illuminated pipeline
  - Soft warning/muted optional layer: `#FF6B6B` at reduced opacity for audio-as-optional, not as an error signal
  - Opacity rules:
    - primary focus: 1.0
    - contextual supporting elements: 0.35 to 0.45
    - background grids, path rails, and inactive placeholders: 0.15

- Typography
  - Use one monospace family throughout, ideally `Menlo`
  - Title size: 46 to 48
  - Section labels: 30 to 34
  - File names and code-adjacent labels: 22 to 24
  - Small path annotations: 18 to 20
  - Keep long paths constrained in width and use line breaks instead of tiny text

- Pacing
  - Opening title reveal: 1.5 seconds, then 1.0 second pause
  - File-to-brief and brief-to-folder transforms: 1.5 to 2.0 seconds, then 1.5 second pause
  - Runtime/dependency build-up: slightly faster cadence, around 0.8 seconds per dependency cluster
  - Final full-pipeline reveal: 2.5 seconds, then a 2.5 to 3.0 second hold
  - Overall tempo curve:
    - Scene 1 slow
    - Scenes 2 to 3 medium
    - Scenes 4 to 6 medium-fast
    - Scene 7 slow and conclusive

- Reusable visual motifs
  - File cards that collapse into more structured artifacts
  - Folder-as-container metaphor for project scaffolding
  - Left-to-right rails with arrows to show irreversible pipeline progress
  - Glow-up transitions where dim placeholders become active, indicating a handoff succeeded
  - Parallel lanes for “video artifact” and “archived brief” in the final scene
  - Consistent bottom caption strip for short narration subcaptions

# Optional Narration Draft

“Here’s the easiest way to think about Hermes building a video explainer.

It doesn’t go straight from request to render.

First, Hermes reads the source material and turns it into a structured brief. That brief defines the audience, the takeaway, the narrative arc, the scene plan, and the visual language.

Then that brief becomes a real project scaffold. A helper script creates a dated project directory in Jellyfin-backed storage and writes out the core files: the brief itself, a source packet, a starter Manim script, a render helper, and a plan.

And there’s an important design choice here: this workflow is visual-first. Audio is optional. The default product is a silent explainer whose ideas should still read clearly on screen.

For rendering, Hermes relies on a local Manim environment on the VPS. The setup script creates or repairs a dedicated venv, installs Manim 0.20.1, verifies the `manim` and `cairo` Python modules, and checks that the Manim binary actually works. The deploy script installs the required system packages before that step, so the render path is part of the normal repo workflow.

From there, the render helper points at the local Manim binary, starts with draft-quality scene renders, and supports a clean path toward final output.

And when the work is done, the result is not just an MP4 sitting in a random folder. The video lives in Jellyfin-backed storage, and the brief is archived in the shared wiki.

So the real story is this: Hermes builds explainers by chaining together a grounded brief, a repeatable scaffold, a verified local render runtime, and a media delivery path that stays useful after the render is finished.”

# Build Notes

- Implement this as 7 Manim scenes, one class per scene, with shared constants at the top:
  - `BG = "#1C1C1C"`
  - `PRIMARY = "#58C4DD"`
  - `SECONDARY = "#83C167"`
  - `ACCENT = "#FFFF00"`
  - `WARN = "#FF6B6B"`
  - `MONO = "Menlo"`

- Use a consistent scene naming scheme such as:
  - `Scene1_RequestToPipeline`
  - `Scene2_SourcesBecomeBrief`
  - `Scene3_BriefBecomesProject`
  - `Scene4_VisualFirstNotAudioFirst`
  - `Scene5_LocalRuntimeLayer`
  - `Scene6_RenderHelperToMp4`
  - `Scene7_ArchiveAndDelivery`

- Favor transforms over cuts:
  - source file cards should transform into `brief.md`
  - `brief.md` should transform into the project folder
  - the four pipeline placeholders from Scene 1 should return in Scene 7 as the final recap motif

- Keep each scene to roughly 10 to 18 seconds.
  - Total runtime target: about 90 seconds
  - Do not overcrowd frames; keep simultaneous active elements under about 6

- Add subcaptions on every major animation beat.
  - The narration draft can be used as subcaption source material even if the final video stays silent

- Pause placement is critical:
  - After the opening title appears: pause 1.0 seconds
  - After `brief.md` fully forms from the source files: pause 1.5 to 2.0 seconds
  - After the project folder expands to reveal its files: pause 1.5 seconds
  - After the “silent by default” visual lands: pause 2.0 seconds
  - After the runtime stack finishes building: pause 1.5 seconds
  - After the draft-to-final render reveal: pause 1.5 seconds
  - After the final full-pipeline recap: pause 2.5 to 3.0 seconds

- For implementation details:
  - use `Text(..., font=MONO)` for all prose labels
  - use `MathTex` only if needed for symbolic arrows or compact notation; this concept does not require much math
  - keep path labels in smaller monospace text and constrain width to avoid overflow
  - set `self.camera.background_color = BG` in every scene
  - end each scene with a clean `FadeOut(Group(*self.mobjects))` and a short `self.wait(0.3)`

- Render workflow:
  - iterate with `-ql`
  - only move to higher quality after verifying spacing, read time, and scene transitions
  - keep raw Manim build artifacts out of the final served delivery area; the story should imply that the clean MP4 is the deliverable, not the intermediate render folders
