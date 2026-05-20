# Video Explainer Pipeline Overview Brief

Captured: 2026-04-19
Type: generated brief
Purpose: Archive explainer briefs in the shared wiki so they are easy to find and reuse.

## Provenance
- Pipeline: `video-explainer-pipeline`
- Title: `Video Explainer Pipeline Overview`

## Content
# Overview

This explainer shows the operator-facing flow of the Hermes video-explainer pipeline as a clean visual handoff: Hermes ingests and normalizes source material, generates a structured brief, archives that brief into the shared wiki, turns the brief into Manim scenes, renders an MP4 into Jellyfin-backed storage, and delivers the result through Jellyfin over Tailscale. The emphasis is not on flashy media production, but on a repeatable VPS workflow that keeps source context, build artifacts, and final delivery in predictable places.

# Audience

Operators working in Hermes stack who need to understand how the video-explainer-pipeline skill fits together, what the canonical scaffold tool does, where outputs live, and why the pipeline defaults to a silent visual-first render.

# Core Takeaway

The video-explainer pipeline is a visual-first Hermes workflow: it ingests sources, produces a scene-structured brief, archives that brief into the shared wiki, scaffolds Manim project files under Jellyfin-backed storage, and renders delivery-ready MP4s that Jellyfin can serve over Tailscale.

# Source Notes

- The pipeline skill is for turning source material into a polished explainer video with NotebookLM-style pacing and structure, rendered with Manim and served from Jellyfin.
- The architecture is explicitly: source extraction and normalization by Hermes, brief generation with narrative arc and scene plan, Manim scene implementation and MP4 rendering, wiki archival of the brief, and Jellyfin delivery.
- Audio policy is explicit: silent by default, with narration or soundtrack treated as an optional later layer.
- The canonical scaffold tool is `/opt/hermes/scripts/make-manim-video.py`.
- That helper creates a project directory under `/data/jellyfin/videos/ai-generated/<series>/<date_slug>/`, can generate `brief.md`, archives the brief into `/home/hermes/sync/wiki/raw/transcripts/media/video-explainers/`, and writes `source-packet.md`, `script.py`, and `render.sh`.
- Default output root is `/data/jellyfin/videos/ai-generated/`.
- Default series slug is `notebooklm-style-explainers`.
- Jellyfin assumptions are: host media root `/data/jellyfin/videos`, container mount `/media/videos`, and serving over a Tailscale URL on port `8096`.
- First-run delivery depends on Jellyfin having a library pointed at `/media/videos`.
- Workflow guidance says to gather sources, scaffold or create the project, generate/refine `brief.md`, archive the brief, implement Manim scenes, render drafts first with `-ql`, then final output with `-qh` if needed, place the MP4 in the Jellyfin-backed tree, and report exact paths.
- Pitfalls worth surfacing: the scaffold helper does not render the finished film by itself, NotebookLM pacing should stay visual-first rather than audio-first, and generated videos should stay under `/data/jellyfin/videos` if they should be served automatically.

# Narrative Arc

Start with the operator’s question: “What actually happens when Hermes makes one of these explainer videos?” Then show the pipeline as a sequence of durable handoffs rather than a black box. First, sources are gathered and normalized. Second, Hermes converts those sources into a brief with a narrative arc and scene plan. Third, that brief is archived into the shared wiki so the reasoning is preserved, not lost inside a render folder. Fourth, Manim takes over for visual execution, turning the brief into scene classes and draft-to-final renders. Finally, Jellyfin becomes the delivery surface, serving the finished MP4 from the same storage tree where the project already lives. The “aha” is that this is one continuous operator-friendly pipeline, not a pile of disconnected creative steps.

# Scene Plan

## scene_01_pipeline_question
- Goal: Frame the pipeline as an operator workflow, not a media mystery.
- On-screen visuals:
  - Title card: “Video Explainer Pipeline Overview”
  - A compact horizontal pipeline skeleton with dim placeholders: Sources → Brief → Wiki Archive → Manim Render → Jellyfin
  - Only the title and first node fully bright
- Narration beats:
  - “Here’s the operator view of the Hermes video-explainer pipeline.”
  - “It starts with source material, stays visual-first, and ends with a Jellyfin-delivered MP4.”
  - Pause after the full pipeline appears.

## scene_02_source_ingestion
- Goal: Show that Hermes begins by extracting and normalizing source material.
- On-screen visuals:
  - Incoming documents/cards labeled “URL”, “notes.md”, “source material”
  - These merge into a single normalized packet
  - Caption: “Hermes extracts and normalizes the source material”
- Narration beats:
  - “The first step is source ingestion.”
  - “Hermes gathers the material and normalizes it into something the rest of the pipeline can work with consistently.”
  - “This is the foundation for every later scene.”
  - Pause after the merge completes.

## scene_03_brief_generation
- Goal: Emphasize that the core product of Hermes is a structured explainer brief.
- On-screen visuals:
  - The normalized packet transforms into a document labeled `brief.md`
  - Callouts appear around the document: “core takeaway”, “target audience”, “narrative arc”, “5–9 scene beats”
  - A secondary document appears beside it: “scene plan”
- Narration beats:
  - “Hermes does not jump straight from source to final video.”
  - “It first generates a structured brief with a clear narrative arc and scene plan.”
  - “That brief is the contract between source understanding and visual execution.”
  - Pause after the callouts settle.

## scene_04_wiki_archival
- Goal: Show that the brief is archived into the shared wiki as a durable artifact.
- On-screen visuals:
  - `brief.md` duplicates
  - One copy travels into a folder tree labeled `/home/hermes/sync/wiki/raw/transcripts/media/video-explainers/`
  - The folder glows as the archive destination
  - Small tag: “shared, searchable, easy to find later”
- Narration beats:
  - “Before rendering, the brief is archived into the shared wiki.”
  - “That matters operationally because the explainer logic is preserved outside the render directory.”
  - “The brief becomes a reusable artifact, not just an intermediate file.”
  - Pause after the archive path is fully revealed.

## scene_05_project_scaffold
- Goal: Introduce the canonical scaffold helper and the project files it creates.
- On-screen visuals:
  - Terminal-style panel showing `/opt/hermes/scripts/make-manim-video.py`
  - Output tree builds beneath it:
    - `/data/jellyfin/videos/ai-generated/<series>/<date_slug>/`
    - `brief.md`
    - `source-packet.md`
    - `script.py`
    - `render.sh`
  - `script.py` and `render.sh` receive subtle highlight pulses
- Narration beats:
  - “The canonical scaffold tool is make-manim-video.py.”
  - “It creates the project directory under Jellyfin-backed storage and writes the key working files.”
  - “That includes the brief, a source packet, a starter Manim script, and a render helper.”
  - Pause after the tree finishes drawing.

## scene_06_manim_execution
- Goal: Show the handoff from brief to scene-based visual implementation.
- On-screen visuals:
  - `brief.md` slides left, `script.py` slides right
  - Arrows connect scene beats to scene classes
  - A draft render badge appears: `-ql`
  - Then a polished render badge appears: `-qh`
  - Final artifact resolves into a single MP4 tile
- Narration beats:
  - “From here, Manim takes the brief and turns it into scene classes.”
  - “The intended workflow is draft first at low quality, then final output at higher quality if needed.”
  - “The render is visual-first. Silence is the default, with audio only as an explicit later layer.”
  - Pause after the MP4 appears.

## scene_07_jellyfin_delivery
- Goal: Show where the final video lives and how it becomes browsable.
- On-screen visuals:
  - MP4 tile lands in `/data/jellyfin/videos/ai-generated/`
  - That path maps to a Jellyfin panel labeled `/media/videos`
  - A Tailscale delivery arrow extends to a browser-style tile labeled `:8096`
  - A side note appears: “Library must point at /media/videos”
- Narration beats:
  - “The final MP4 stays in the Jellyfin-backed project tree.”
  - “Jellyfin serves from the mounted videos library, and operators can reach it over Tailscale.”
  - “The important operational detail is simple: keep outputs under the videos root if you want them served automatically.”
  - Pause after the delivery arrow lands.

## scene_08_operator_summary
- Goal: End with one memorable operator mental model.
- On-screen visuals:
  - Full pipeline returns in one line
  - Each stage lights up in sequence:
    - Ingest
    - Brief
    - Archive
    - Render
    - Deliver
  - Final centered takeaway text:
    - “One pipeline.”
    - “Visual-first.”
    - “Archived.”
    - “Delivered.”
- Narration beats:
  - “So the pipeline is not just about rendering animation.”
  - “It is a repeatable operator workflow for ingesting sources, preserving intent in the wiki, rendering with Manim, and delivering through Jellyfin.”
  - “That is the video-explainer pipeline in Hermes stack.”
  - Long closing pause.

# Visual Language

- Palette:
  - Background: `#1C1C1C`
  - Primary: `#58C4DD`
  - Secondary: `#83C167`
  - Accent: `#FFFF00`
  - Archive/Wiki emphasis: slightly warmer green-yellow blend for persistence moments
  - Structural lines and inactive nodes at low opacity around 0.15 to 0.25
- Typography:
  - Monospace throughout for visual consistency in Manim
  - Title size around 48
  - Section/scene heading size around 36
  - Body/callout text around 28 to 30
  - Labels/path text around 20 to 24
- Pacing:
  - Conversational and steady, closer to NotebookLM rhythm than to a lecture
  - Short scene builds, one idea per beat
  - Use visible settling time after each structural reveal
  - Keep transitions clean and causal: transforms, path tracing, staged highlights
- Reusable visual motifs:
  - Horizontal pipeline spine for the overall system
  - File cards for `brief.md`, `source-packet.md`, `script.py`, `render.sh`
  - Folder-tree reveals for wiki and Jellyfin storage paths
  - Arrow handoffs to show process ownership changes
  - Opacity layering: current focus at full brightness, adjacent context dimmed
  - Sequential illumination of pipeline nodes to reinforce causality
  - Terminal-style command block only once, for the scaffold helper, so it feels canonical rather than repetitive

# Optional Narration Draft

This video explains the operator flow behind the Hermes video-explainer pipeline.

It starts with source ingestion. Hermes gathers the input material and normalizes it into a consistent source packet.

Then Hermes generates a structured brief. That brief carries the core takeaway, the audience, the narrative arc, and the scene plan. It is the bridge between source understanding and visual production.

Next, the brief is archived into the shared wiki. That keeps the explainer logic durable and easy to find later, instead of burying it inside a render folder.

From there, the scaffold tool creates the project under Jellyfin-backed storage and writes the working files, including the brief, source packet, starter Manim script, and render helper.

Manim then turns the brief into scene-based visuals. Draft renders come first, final renders later, and the default mode stays silent unless audio is explicitly requested.

The final MP4 remains under the Jellyfin videos tree, where Jellyfin can serve it over Tailscale once the library is pointed at the mounted media path.

So the core idea is simple: ingest the source, preserve the brief, render with Manim, and deliver through Jellyfin.

# Build Notes

- Implement this as 8 short Manim scenes, one class per scene, so each scene is independently renderable and easy to revise.
- Set a consistent dark background in every scene and keep the same palette constants at the top of `script.py`.
- Use monospace text only.
- Keep path strings and filenames large enough to read on first viewing; avoid tiny terminal text blocks.
- Represent the workflow with transforms rather than cuts whenever possible:
  - source cards merge into one normalized packet
  - normalized packet transforms into `brief.md`
  - `brief.md` duplicates so one copy can move into the wiki archive path
  - scene beats transform into `script.py` scene blocks
  - render badges resolve into an MP4 tile
- Show the scaffold helper exactly as `/opt/hermes/scripts/make-manim-video.py`.
- Show the archive root exactly as `/home/hermes/sync/wiki/raw/transcripts/media/video-explainers/`.
- Show the output root exactly as `/data/jellyfin/videos/ai-generated/`.
- Show the Jellyfin mount exactly as `/media/videos`.
- Show silence as the default by using a small “silent by default” tag during the Manim/render scene rather than over-explaining it everywhere.
- Pause points:
  - after the full pipeline first appears
  - after source normalization completes
  - after the brief callouts settle
  - after the wiki archive path is revealed
  - after the scaffold tree finishes building
  - after the final MP4 appears
  - after the Jellyfin/Tailscale delivery path lands
  - longest pause on the final takeaway frame
- Draft render at `-ql` first to validate spacing, readability, and pause length.
- Only move to higher-quality render after verifying that path text, file labels, and opacity hierarchy all read cleanly.
- Keep the final visual thread narrow: ingest, brief, archive, render, deliver. Avoid adding extra side branches that are not directly supported by the source.
