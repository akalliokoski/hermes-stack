---
name: video-explainer-pipeline
description: Create NotebookLM-style explainer videos on the VPS by reusing Hermes source-ingestion patterns, infographic slide/scene rendering, optional later audio, shared wiki transcript archives, and Jellyfin delivery for finished MP4s.
---

# Video Explainer Pipeline

Use this skill when the user wants Hermes to turn source material into a polished explainer video with NotebookLM-style pacing and structure, rendered as infographic-style slides/scenes and served from Jellyfin.

This skill is intentionally thin. Reuse:
- `baoyu-infographic` for scene/slide craft, layout thinking, and infographic visual language
- `podcast-pipeline` for VPS-first ingestion/orchestration patterns and artifact archival ideas
- `hermes-stack` repo tools for the actual runtime workflow

## Architecture

- Hermes extracts and normalizes the source material.
- Hermes generates a structured explainer brief with a clear narrative arc and scene plan.
- The default visual backend is infographic-style slides/scenes derived from `scene_manifest.json`, not Manim.
- If the project is narrated, the pipeline becomes narration-spec-first:
  - Hermes writes a canonical scene manifest plus per-scene narration script.
  - TTS is synthesized per scene to obtain real voice durations.
  - The scene manifest is updated with measured audio timings, pause budgets, and beat windows.
  - The infographic renderer reads that manifest and renders visuals that conform to the narration timing instead of treating pre-rendered scene durations as fixed.
- Output lives under `/data/jellyfin/videos/ai-generated/` on the VPS.
- Jellyfin serves the resulting videos over Tailscale.
- The brief and narration artifacts are archived into the shared wiki so they are easy to find later.

## Audio policy

Default mode is **no audio**.

That means:
- the pipeline should produce a silent visual explainer by default
- narration, voiceover, or soundtrack are optional later additions
- if audio is desired, treat it as an explicit opt-in layer on top of the visual-first workflow

Do not assume every explainer needs narration.

## Canonical repo tool

Primary helper:

```text
/opt/hermes/scripts/make-manim-video.py
```

What it does:
- creates a repeatable project directory under `/data/jellyfin/videos/ai-generated/<series>/<date_slug>/`
- optionally asks Hermes to generate `brief.md`
- archives the brief into the shared wiki under `raw/transcripts/media/video-explainers/`
- writes `source-packet.md`
- writes `slides.md`
- writes `render.sh`
- writes `scene_manifest.json` for both silent and narrated projects
- in narrated mode, also writes `narration-script.md`
- keeps project assets in Jellyfin-backed storage from the start

Related repo helpers for narrated mode:
- `/opt/hermes/scripts/video_scene_manifest.py`
- `/opt/hermes/scripts/video_audio_timeline.py`
- `/opt/hermes/scripts/video_voice_calibration.py`
- `/opt/hermes/scripts/render_infographic_from_manifest.py`

Example:

```bash
python3 /opt/hermes/scripts/make-manim-video.py \
  --title "How Transformers Route Information" \
  --url https://example.com/post \
  --source-file /path/to/notes.md
```

If the user explicitly wants audio later:

```bash
python3 /opt/hermes/scripts/make-manim-video.py --title "..." --with-audio ...
```

## Output layout

Default host output root:

```text
/data/jellyfin/videos/ai-generated/
```

Default series slug:

```text
notebooklm-style-explainers
```

Shared wiki archive root:

```text
/opt/hermes/wiki/raw/transcripts/media/video-explainers/
```

## Jellyfin delivery

Jellyfin is the video-serving layer in `hermes-stack`.

Runtime assumptions:
- host media root: `/data/jellyfin/videos`
- Jellyfin container mount: `/media/videos`
- tailnet URL: `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:8096/`

First-run note:
- create a Jellyfin library that points at `/media/videos`
- after that, new renders copied under `/data/jellyfin/videos/...` become browsable from Jellyfin

## Workflow

When asked to make a video:

1. Gather the source material.
2. Run the scaffold helper or manually create the project structure.
3. Generate or refine `brief.md`.
4. Archive the brief into the shared wiki.
5. If the video is silent, use `baoyu-infographic` guidance plus the repo render helpers to turn the Scene Plan into infographic slides/scenes and render normally.
6. If audio is requested, switch to a narration-spec-first workflow:
   - write a canonical `scene_manifest.json` (or `.yaml`) with scene ids, narration goals, beat windows, pause budgets, and target visual motifs
   - write narration **per scene**, not as one monolithic transcript
   - calibrate the production voice once with the actual TTS backend/voice settings and store the measured words-per-second in config or the manifest
   - synthesize one TTS clip per scene using the `podcast-pipeline` backend or another compatible TTS path
   - measure each clip with `ffprobe` and record the real durations back into the manifest
   - if a clip overruns its speech window, resolve it in this order: trim filler words, allow a small `ffmpeg atempo` speed-up (roughly 1.03 to 1.08), spend available pause slack, rewrite, then extend the scene timing if needed
   - normalize each scene clip to a consistent loudness target before assembly
   - generate the final narration bed from the manifest timeline, snapping offsets to frame boundaries when needed
   - if narration text is still blank, skip TTS/assembly and treat the project as an unfinished narrated scaffold instead of forcing a broken audio pass
7. In the concrete hermes-stack helper flow, do narrated work in this order: synthesize/update manifest timings first, then render infographic scene assets/clips from the manifest, then stitch the final MP4.
8. In the current helper stack, a fresh `render.sh` writes per-scene still slides under `render/slides/`, per-scene clips under `render/clips/`, stitches them into a final MP4, and muxes `audio/master-narration.mp3` into a narrated MP4 when narration exists.
9. If you are re-rendering an older existing project after deploying helper changes, do not assume its local `render.sh` and `slides.md` are current. Re-generate them from the latest repo helpers first, or run the underlying helper scripts directly.
10. Render drafts first, then final output if needed, and keep enough visual hold time after key reveals for comprehension.
11. Place the final MP4 and any canonical narration/manifest artifacts in the Jellyfin-backed project tree.
12. Before calling the job complete, remove or move intermediate render artifacts out of the served Jellyfin path so only delivery assets remain indexable.
13. Force a Jellyfin library refresh and verify the exact new item(s) through the API or DB-backed inspection path instead of assuming passive scan timing will pick them up.
14. Archive the text artifacts into the shared wiki, and tell the user the exact output paths plus confirm the video is now available in Jellyfin.

## Prompting guidance

When Hermes generates the brief, ask for:
- one-sentence core takeaway
- target audience
- narrative arc
- 5 to 9 scene beats
- per-scene goal, visuals, and narration beats
- reusable palette and typography rules
- explicit pause moments
- an **optional** narration section, not mandatory voiceover

If the user wants an audio version, add these implementation constraints before writing narration:
- narration is the timing authority for narrated explainers
- the first durable output is a canonical scene manifest, not a final MP4
- each scene needs authored beat windows, pause budget, and target visual motifs
- each scene needs a max word budget derived from the calibrated production voice, not a generic assumed WPM
- write narration **per scene** with punctuation chosen to create natural pauses because the TTS backend may not support SSML break tags cleanly
- after synthesis, update the manifest with measured clip durations and let Manim conform to those timings
- subtitles/subcaptions should derive from the same manifest + narration alignment data rather than being authored as an unrelated layer

## Environment / config

Useful env vars:
- `VIDEO_OUTPUT_DIR=/data/jellyfin/videos/ai-generated`
- `VIDEO_SERIES=notebooklm-style-explainers`
- `VIDEO_PIPELINE_VENV=/home/hermes/.venvs/video-pipeline`
- `JELLYFIN_BASE_URL=http://127.0.0.1:8096`
- `WIKI_PATH=/opt/hermes/wiki`

## Local infographic runtime on hermes-stack

Current preferred runtime on the VPS is a lightweight local venv plus `ffmpeg`, not Manim.

Canonical bootstrap helper:

```text
/opt/hermes/scripts/setup-video-pipeline.sh
```

What it does:
- creates/repairs the dedicated venv at `/home/hermes/.venvs/video-pipeline`
- ensures `pip` exists in that venv
- verifies the Python runtime and `ffmpeg` availability for the infographic render path

Repo deploy behavior:
- `scripts/remote-deploy.sh` installs the required Ubuntu packages before bootstrapping the venv
- current required package is:
  - `ffmpeg`

Operational lesson:
- if the venv exists but the renderer still fails, first verify `ffmpeg` is installed and the repo-side helpers are current
- on hermes-stack, fix that repo-first and redeploy instead of introducing a separate ad hoc render path

## Pitfalls

- `make-manim-video.py` scaffolds the project; it does not magically render a finished film by itself.
- Existing project directories keep the generated `render.sh`, `script.py`, manifest, and related artifacts that were present when the scaffold was created. If the repo helper logic changes later, old projects do not automatically inherit those fixes — regenerate the project-local generated files or re-scaffold before assuming the latest helper behavior applies.
- Before telling the user a rendered explainer has no audio, inspect the actual MP4 with `ffprobe` and confirm whether an audio stream already exists. A project may contain both a silent MP4 and a separate `*-narrated.mp4`, so checking only the silent file can lead to a wrong status report.
- For freshly generated narrated projects on the current helper stack, `render.sh` is intended to be a genuine one-command path: it synthesizes narration assets, regenerates `script.py` from the manifest, renders all scenes by default, stitches them into a final MP4, and muxes a narrated MP4 when `audio/master-narration.mp3` exists.
- NotebookLM-style pacing does not mean wall-to-wall speech. Silence and visual hold time are part of comprehension.
- Jellyfin will not show anything useful until its library is pointed at `/media/videos`.
- A fresh Jellyfin deploy may still report `StartupWizardCompleted: false`; media files can already be in the correct mounted path even before the UI/library setup is finished.
- Do not store generated videos outside `/data/jellyfin/videos` if you want them served automatically.
- Draft at low quality first. Do not jump straight to expensive high-quality renders.
- Do not assume narration is required. Silence is the default mode.
- On this VPS, the configured `VIDEO_PIPELINE_VENV` may exist but still be unusable for rendering (for example: no `pip`, no `manim`, or missing build dependencies). Verify it explicitly before relying on it.
- Prefer a **local Manim install** guided by the `manim-video` skill. The official Manim Community docs recommend local pip/uv installation, not Docker as the default workflow.
- For Ubuntu/Debian, install the build/runtime prerequisites first: `build-essential python3-dev pkg-config libcairo2-dev libpango1.0-dev ffmpeg` and optionally `texlive-full` if you need LaTeX math rendering.
- After system prerequisites exist, install Manim into the dedicated video venv (or a project-local uv environment) and verify with `manim --version` plus `python -c 'import manim, cairo'`.
- Treat Docker rendering only as an explicit last-resort fallback, not the normal path.
- After copying a finished MP4 into the Jellyfin-backed tree, trigger a Jellyfin library refresh and verify the item via the API instead of assuming passive scan timing will be good enough.
- Do not leave raw Manim build artifacts like `media/videos/...` and `partial_movie_files/...` under the served Jellyfin tree unless you want them indexed as separate videos.
- In practice, Jellyfin may also index non-video project directories and helper artifacts (for example `media/`, `__pycache__/`, and other scaffold leftovers) as folders/items under the library. For a clean media library, keep the served project directory as delivery-only as possible.
- Best practice: after rendering, move intermediate Manim artifacts and cache directories out of `/data/jellyfin/videos/...` into a separate archive location, leaving the final MP4 as the primary served artifact before refreshing Jellyfin.
- For the cleanest Jellyfin delivery, go further than removing `media/` and `partial_movie_files/`: archive non-delivery helper artifacts like `audio/`, `captions/`, `brief.md`, `narration-script.md`, `scene_manifest.json`, `script.py`, `render.sh`, and similar project metadata out of the served directory too, leaving only the final delivery MP4(s) indexable.
- If you clean a served project that aggressively, keep a matching archive directory for the project so you can restore `scene_manifest.json`, `render.sh`, `narration-script.md`, `brief.md`, and other runtime artifacts before a future rerender. A good iterative workflow is: restore archived project artifacts -> rerender -> archive non-delivery files again -> refresh Jellyfin -> verify indexed items.
- For clearer narrated explainers, some scenes benefit from scene-specific diagrams instead of generic bullet cards. In practice, runtime/setup scenes and delivery/archive scenes improved when rendered as explicit node/arrow diagrams (for example: a venv capsule with dependency nodes and arrows; or final MP4 / Jellyfin / wiki-archive nodes with arrows) rather than as text-heavy cards.
- When regenerating a narrated explainer from an older scaffold, stale local copies of `render.sh` or `script.py` may still reflect pre-manifest behavior even after the repo helpers were fixed. Re-generate those project-local files from the current `/opt/hermes/scripts/...` helpers before trusting the render path.
- `video_audio_timeline.py assemble` previously had a relative-path bug around concat outputs; the current repo/helper version now creates parent directories and resolves concat/output paths correctly, but old deployed or copied scripts may still have the broken behavior.
- A separate audio-assembly failure mode: if `ensure_wav_from_clip` lets ffmpeg/loudnorm emit clip WAVs at a different sample rate than the generated silence segments (for example clip WAVs at 192000 Hz but silence at 44100 Hz), concat-demuxing those WAVs can produce a master narration track with dramatically slowed, broken speech. Force a single concat-safe PCM format for every segment before concatenation (for example `-ar 44100 -ac 1 -c:a pcm_s16le`) and verify the rebuilt `master-narration.mp3` duration matches the manifest/video runtime.
- Older helper versions also failed to render all scenes by default for manifest-driven projects unless `manim -a` was used. The current helper stack fixes that, but stale generated `render.sh` files can still show the old prompt/select behavior.
- If the user wants narration, do not generate one full podcast-style track and trim/mux it over an already-finished video. That only matches total runtime, not scene semantics.
- For narrated explainers, make the scene manifest the single source of truth and let video, TTS, and captions all derive from it.
- The manifest-driven renderer must not dump full `narration_text` paragraphs onto the screen as the main visual. Keep narration in timing/subcaptions, and drive visuals from structured fields like `visual_motif`, `visual_bullets`, layout primitives, and beat metadata so narrated renders remain real Manim explainers instead of text slides.
- On this VPS, `Menlo` is not installed. Prefer an actually installed fallback such as `DejaVu Sans Mono` (and `DejaVu Sans` for supporting labels) in repo-side Manim helpers so renders avoid font warnings and spacing drift.
- Do not hard-code a generic 125 WPM budget without calibrating the actual production voice first.
- If a scene clip barely overruns budget, do not jump straight to a full rewrite. Use an escalation ladder: trim filler, minor `atempo`, spend pause slack, rewrite, then extend the scene.
- Normalize narration loudness before assembly, or scene-to-scene transitions will sound amateurish even if timing is correct.
- If narration still does not fit after text cleanup, the right fix is often to extend the Manim hold/scene duration and re-render, not to crush speech unnaturally.
- When deriving `scene_manifest.json` from `brief.md`, only treat top-level Scene Plan items as scenes. Nested bullets like Goal/Visuals/Narration Beats are metadata, not extra scenes.
- Current practical failure mode to watch for: a freshly scaffolded narrated project can still misparse some existing explainer briefs into many bogus scenes such as `On-screen visuals` and `Narration beats`, leaving every `narration_text` blank. If that happens, do not trust the fresh scaffold as-is.
- Recovery path for that failure: inspect `scene_manifest.json` and `narration-script.md` immediately after scaffolding. If you see empty narration plus bogus scene ids derived from metadata headings, replace/regenerate those project-local artifacts from a known-good manifest/script (or fix the parser repo-first) before rerunning `render.sh`.
- If you update the repo-side narrated renderer after a project was already scaffolded, do not just rerun the old project blindly. Refresh the project-local `scene_manifest.json` from `brief.md` so structured fields like `goal`, `visual_motif`, and `visual_bullets` are populated from the Scene Plan, then regenerate `script.py` from the refreshed manifest before rendering.
- General design guidance for future explainers: ask for short noun-phrase visual bullets, not sentence fragments; prefer one hero object plus 2 to 3 supporting nodes with explicit arrows/containment; and for dense scenes (for example runtime/deployment or delivery/archive scenes), use specialized diagrams rather than generic text cards.
- Repo-level implementation lesson: encode those design constraints directly in `scripts/make-manim-video.py` so newly generated briefs already bias toward diagram-friendly Scene Plan output instead of requiring per-project cleanup later.
- The repo-side narrated renderer in `scripts/render_manim_from_manifest.py` should use installed VPS fonts (`DejaVu Sans Mono` / `DejaVu Sans` here), larger supporting text, semantic icons, and specialized diagrams for dense scenes like runtime/dependency and delivery/archive stages. Keep narration in subcaptions, not as on-screen paragraph text.
- Repo-generated `render.sh` should prefer repo helper paths first (for example `/home/hermes/work/hermes-stack/scripts/...`), then fall back to `/opt/hermes/scripts/...`, so newly scaffolded projects inherit renderer improvements without needing manual local patches.
- Newly generated narrated projects should clean `media/` and `__pycache__` out of the served Jellyfin tree by default after stitching the final MP4s (for example into `/home/hermes/archive/jellyfin-render-artifacts/<project>/`) so future videos do not leak intermediate Manim files into Jellyfin.
- For final Jellyfin delivery, a good end-state is delivery-only project folders: keep the final silent and narrated MP4s in the served path, archive `brief.md`, `scene_manifest.json`, `narration-script.md`, captions, audio work files, render helpers, and other supporting artifacts outside the served tree, then trigger a Jellyfin refresh and verify only the final MP4 items are indexed.
- For existing projects, prefer a project-local `render.sh` that points at the current repo helper paths first (for example `/home/hermes/work/hermes-stack/scripts/render_manim_from_manifest.py` and `video_audio_timeline.py`) and only falls back to `/opt/hermes/scripts/...` if the repo copy is unavailable. Otherwise older projects can silently keep using stale helper behavior even after the repo was fixed.
- In narrated mode, if `narration_text` is blank, skip synthesis/assembly and surface that the scaffold still needs authored narration instead of trying to build a broken master track.
- Manifest-driven render helpers must budget fade-in, hold time, and fade-out inside `scene_duration_s`; otherwise the rendered video drifts longer than the narration timeline.

## Verification checklist

Before claiming success:
1. Confirm the project directory exists under `/data/jellyfin/videos/ai-generated/...`
2. Confirm `brief.md`, `source-packet.md`, and `slides.md` were written
3. Confirm the brief was archived under the shared wiki transcript root
4. Confirm the project has a canonical `scene_manifest.json`, and a narrated project also has per-scene narration source archived in the project and wiki
5. If narration is enabled, confirm voice calibration or measured scene clip durations and final timeline offsets were recorded
6. If rendered, confirm the final MP4 exists
7. Confirm Jellyfin is reachable on the tailnet URL or local `127.0.0.1:8096`
8. Tell the user the exact output paths

## Full flow summary

```text
User asks Hermes for an explainer video
→ Hermes extracts and normalizes sources
→ Hermes generates a structured brief
→ brief archived into /opt/hermes/wiki/raw/transcripts/media/video-explainers/
→ scene_manifest.json becomes the canonical scene/timing contract
→ if silent: infographic slides/scenes are rendered directly from the manifest
→ if narrated: Hermes writes a per-scene narration script, TTS is synthesized per scene, and durations are measured back into the manifest
→ captions/subcaptions derive from the same manifest/alignment data
→ final scene clips are stitched into an MP4 under /data/jellyfin/videos/ai-generated/
→ Jellyfin serves the result over Tailscale
→ Hermes sends the user the output path / viewing instructions
```
