# How Hermes Builds Video Explainers Narration-Script

Captured: 2026-04-20
Type: generated narration-script
Purpose: Archive narrated explainer scripts in the shared wiki so timing-authoritative narration specs are easy to find and reuse.

## Provenance
- Pipeline: `video-explainer-pipeline`
- Title: `How Hermes Builds Video Explainers`

## Content
# Narration Script

Narration is the timing authority for narrated explainers.

## S1_request_to_pipeline

Goal: Introduce the user-facing promise and frame the workflow as a sequence rather than a black box.

Narration:
At first glance, this sounds like one request: make a video. But Hermes handles it as a pipeline. First the brief, then the project scaffold, then the render environment, and finally delivery.

## S2_sources_become_brief

Goal: Show that Hermes starts by reading provided inputs and generating a structured explainer brief.

Narration:
The first job is source digestion. The helper script builds a strict prompt, asks Hermes to read the supplied local files, and requires a structured markdown brief. That brief is not filler. It defines the narrative arc, scene beats, visual language, and build notes.

## S3_brief_becomes_project

Goal: Make the scaffold step feel tangible and concrete.

Narration:
Next, Hermes does not start from scratch each time. `make-manim-video.py` creates a dated project directory in Jellyfin-backed storage. It writes the brief, records the source packet, creates a starter Manim script, writes a render helper, and stores a plan for implementation.

## S4_visual_first_not_audio_first

Goal: Clarify the pipeline’s design philosophy: visual explainer first, audio optional.

Narration:
One important policy shapes the whole workflow. These videos are silent by default. Narration can be added later, but the pipeline is designed so the visuals stand on their own.

## S5_local_runtime_layer

Goal: Explain how the render environment is prepared and why local Manim matters.

Narration:
Rendering depends on a dedicated local runtime. `setup-video-pipeline.sh` repairs or creates the venv, ensures pip exists, installs Manim 0.20.1, and verifies both `manim` and `cairo`. And `remote-deploy.sh` installs the required Ubuntu packages first, so the render path is part of normal repo deployment.

## S6_render_helper_to_mp4

Goal: Connect the scaffold to actual rendering behavior without getting lost in implementation detail.

Narration:
The scaffold includes a render helper that looks for the local Manim binary in the video venv. It starts from scene-based rendering, with a default introduction scene already scaffolded. The intended rhythm is draft first at low quality, then final render once the scenes are right.

## S7_archive_and_delivery

Goal: Land the full system picture: archive, storage, and serving.

Narration:
The end state is operational, not just artistic. The video lives in Jellyfin-backed storage so it can be served from the media library. And the brief is archived into the shared wiki, so the reasoning behind the video stays reusable. That is how Hermes builds explainers: grounded sources, a structured brief, a repeatable Manim scaffold, a verified local runtime, and clean delivery.
