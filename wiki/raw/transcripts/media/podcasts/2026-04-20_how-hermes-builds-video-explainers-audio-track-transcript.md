# How Hermes Builds Video Explainers Audio Track Transcript

Captured: 2026-04-20
Type: generated transcript
Purpose: Archive podcast transcripts in the shared wiki so they are easy to find and reuse.

## Provenance
- Pipeline: `podcast-pipeline`
- Title: `How Hermes Builds Video Explainers Audio Track`

## Content
<Person1>Here is the big idea. Hermes does not jump straight from a request to a finished video.</Person1>
<Person2>It starts by reading the sources and compressing them into a structured brief with the audience, takeaway, scene plan, and build notes.</Person2>
<Person1>Then that brief becomes a real project scaffold inside Jellyfin-backed storage: brief, source packet, script, render helper, and plan.</Person1>
<Person2>Rendering stays local. Deploy installs the Ubuntu packages, the setup script repairs the video venv, and Manim runs from that verified environment.</Person2>
<Person1>From there, Hermes renders the scenes, keeps audio optional by default, archives the brief in the wiki, and writes the final MP4 to Jellyfin.</Person1>
<Person2>So the pipeline is simple: brief, scaffold, local render, and delivery.</Person2>
