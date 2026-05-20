# How Hermes Builds Video Explainers Audio Transcript

Captured: 2026-04-20
Type: generated transcript
Purpose: Archive podcast transcripts in the shared wiki so they are easy to find and reuse.

## Provenance
- Pipeline: `podcast-pipeline`
- Title: `How Hermes Builds Video Explainers Audio`

## Content
<Person1>A request comes in: make an explainer. Hermes does not jump straight to rendering.</Person1>
<Person2>It treats the job as a pipeline: brief first, then scaffold, then the render setup, then delivery.</Person2>
<Person1>To build the brief, Hermes reads the provided project files and turns them into a structured brief.md.</Person1>
<Person2>That brief locks in the audience, core takeaway, scene plan, visual language, and build notes.</Person2>
<Person1>Then make-manim-video.py creates a dated project in Jellyfin-backed storage with brief.md, source-packet.md, script.py, render.sh, and plan.md.</Person1>
<Person2>And the runtime is local, not Docker: setup-video-pipeline.sh repairs the video venv, installs Manim 0.20.1, and verifies manim plus cairo.</Person2>
<Person1>From there, the render helper targets the local Manim binary and the final output becomes an MP4 in /data/jellyfin/videos/ai-generated.</Person1>
<Person2>At the same time, the brief is archived to the shared wiki, so Hermes keeps both the finished video and the reasoning behind it.</Person2>
