# Video Explainer Narration-Spec Refactor Implementation Plan

> **For Hermes:** Use `software-development/subagent-driven-development` if executing this plan later.

**Goal:** Refactor the `video-explainer-pipeline` so narrated explainers treat the narration script plus scene manifest as the authoritative timing spec, with Manim rendering visuals to conform to that spec instead of forcing audio to fit an already-rendered video.

**Architecture:** Keep silent explainers simple, but introduce a narrated mode built around a canonical scene manifest. The manifest owns scene order, beat windows, pause budgets, calibrated voice speed, measured TTS clip durations, frame-snapped offsets, and caption provenance. TTS is synthesized per scene, the manifest is updated with measured timings, Manim reads the manifest to render scene durations and reveal pacing, and the final audio bed / captions / MP4 all derive from the same source of truth.

**Tech Stack:** Python CLI helpers in `scripts/`, local Manim venv, `ffprobe`, `ffmpeg` (`atempo`, `loudnorm`, concat), Chatterbox/OpenAI-compatible TTS via the existing podcast pipeline backend, Jellyfin-backed storage, shared wiki archival.

---

## 1. Current State

### Existing helpers
- `scripts/make-manim-video.py`
  - scaffolds `brief.md`, `source-packet.md`, `script.py`, `render.sh`, `plan.md`
  - currently treats audio as optional later work, but does not produce a canonical scene manifest
- `scripts/make-podcast.py`
  - generates or accepts a transcript, archives it to the wiki, then delegates audio generation
- `scripts/run_podcastfy_pipeline.py`
  - synthesizes a single transcript into one MP3
  - no per-scene clip mode, no loudness normalization, no alignment metadata
- `scripts/podcast_pipeline_common.py`
  - shared output and wiki archival helpers

### Main failure to eliminate
The current narrated video path can produce a full audio file and mux it over the finished silent render. That gives total-runtime sync only. It does not guarantee:
- scene sync
- beat sync
- readable pacing
- aligned captions/subcaptions
- stable repair when narration slightly overruns

---

## 2. Target File/Module Layout

### Modify
- `scripts/make-manim-video.py`
- `scripts/run_podcastfy_pipeline.py`
- `scripts/podcast_pipeline_common.py`
- `SETUP.md`
- `docs/plans/2026-04-20-video-explainer-narration-spec-refactor.md` (this plan; keep updated if scope changes)

### Create
- `scripts/video_scene_manifest.py`
  - manifest dataclasses, schema load/save, validation, frame snapping, timeline math
- `scripts/video_voice_calibration.py`
  - synthesize calibration text, measure actual words/sec for configured voice, store metadata
- `scripts/video_audio_timeline.py`
  - per-scene audio assembly, pause insertion, loudnorm, optional `atempo`, master track build
- `scripts/render_manim_from_manifest.py`
  - render Manim scenes from `scene_manifest.json` / `.yaml`
- `tests/test_video_scene_manifest.py`
- `tests/test_video_audio_timeline.py`
- `tests/test_make_manim_video_scaffold.py`

### Project artifacts each narrated explainer should contain
Inside `/data/jellyfin/videos/ai-generated/<series>/<date_slug>/`:
- `brief.md`
- `source-packet.md`
- `scene_manifest.json`
- `narration-script.md`
- `script.py` or generated Manim scene module
- `audio/scene-*.mp3`
- `audio/master-narration.wav` or `.mp3`
- `captions/final.srt`
- `render.sh`
- final MP4

### Wiki artifacts to archive
Under `/home/hermes/sync/wiki/raw/transcripts/media/video-explainers/`:
- brief archive
- narration script archive
- optional manifest snapshot archive for reproducibility

---

## 3. Canonical Manifest Schema

Use one schema only. Do not store redundant end-times that can be derived.

```json
{
  "version": 1,
  "mode": "narrated",
  "title": "How Hermes Builds Video Explainers",
  "fps": 30,
  "voice": {
    "backend": "openai-compatible",
    "base_url": "https://...",
    "voice_id": "default",
    "calibrated_wps": 2.05,
    "calibration_text_sha256": "...",
    "measured_at": "2026-04-20T12:34:56Z"
  },
  "audio": {
    "target_lufs": -16,
    "max_small_atempo": 1.08
  },
  "scenes": [
    {
      "scene_id": "scene-01-request-to-pipeline",
      "goal": "Introduce the pipeline shape",
      "visual_motif": "pipeline blocks and arrows",
      "narration_text": "Hermes turns a video request into a sequence: brief, scaffold, render, then delivery.",
      "speech_offset_s": 0.8,
      "pause_after_s": 1.2,
      "beats": [
        {"beat_id": "intro", "start_s": 0.0, "kind": "visual"},
        {"beat_id": "pipeline-labels", "start_s": 1.0, "kind": "speech-anchor"}
      ],
      "audio_clip_path": "audio/scene-01.mp3",
      "audio_duration_s": 6.42,
      "scene_duration_s": 8.42,
      "timeline_offset_s": 0.0,
      "caption_source": "forced-alignment"
    }
  ]
}
```

Rules:
- `timeline_offset_s` is authored/computed once and snapped to frame boundaries.
- `scene_duration_s = speech_offset_s + audio_duration_s + pause_after_s` unless an explicit extension is needed.
- captions, Manim timing, and audio assembly all consume this same file.

---

## 4. Implementation Tasks

### Task 1: Add manifest model + validator

**Objective:** Create one canonical schema and helper functions for scene timing math.

**Files:**
- Create: `scripts/video_scene_manifest.py`
- Create: `tests/test_video_scene_manifest.py`

**Step 1: Write failing tests**
Add tests for:
- loading/saving manifest JSON
- rejecting missing `scene_id`
- computing `scene_duration_s`
- snapping `timeline_offset_s` to `1/fps`

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_scene_manifest.py -q
```
Expected: failure because module does not exist.

**Step 3: Implement manifest helpers**
Include:
- dataclasses or typed dict helpers
- `load_manifest(path)`
- `save_manifest(path, manifest)`
- `snap_time(value, fps)`
- `recompute_scene_durations(manifest)`
- `recompute_timeline_offsets(manifest)`
- `validate_manifest(manifest)`

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_scene_manifest.py -q
```
Expected: pass.

**Step 5: Commit**
```bash
git add scripts/video_scene_manifest.py tests/test_video_scene_manifest.py
git commit -m "feat: add video scene manifest schema"
```

---

### Task 2: Add voice calibration helper

**Objective:** Replace guessed WPM budgets with measured voice speed.

**Files:**
- Create: `scripts/video_voice_calibration.py`
- Modify: `scripts/podcast_pipeline_common.py`

**Step 1: Write failing tests**
Add tests in `tests/test_video_audio_timeline.py` for:
- parsing `ffprobe` duration output
- deriving `calibrated_wps = words / seconds`

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```
Expected: failure because helper does not exist.

**Step 3: Implement calibration flow**
`video_voice_calibration.py` should:
- accept backend URL / voice config / output path
- synthesize a fixed calibration paragraph with the production voice
- measure duration with `ffprobe`
- compute words-per-second
- write calibration metadata back into the manifest or a sidecar JSON

Prefer reusing the existing OpenAI-compatible TTS path rather than inventing a second backend.

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```
Expected: pass for calibration helpers.

**Step 5: Commit**
```bash
git add scripts/video_voice_calibration.py scripts/podcast_pipeline_common.py tests/test_video_audio_timeline.py
git commit -m "feat: add video voice calibration helper"
```

---

### Task 3: Teach `make-manim-video.py` to scaffold narrated projects

**Objective:** Produce first-class narration artifacts instead of only `brief.md` + starter script.

**Files:**
- Modify: `scripts/make-manim-video.py`
- Create or modify: `tests/test_make_manim_video_scaffold.py`

**Step 1: Write failing tests**
Test narrated scaffold mode:
- `--with-audio` should create `scene_manifest.json`
- should create `narration-script.md`
- `plan.md` should describe narration-spec-first flow
- should archive narration text to the wiki when present

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_make_manim_video_scaffold.py -q
```
Expected: failure because files are not created yet.

**Step 3: Implement scaffold changes**
Update `make-manim-video.py` to:
- keep silent mode unchanged
- in narrated mode, write initial `scene_manifest.json`
- write `narration-script.md` with one scene section per beat
- archive the narration script with `archive_generated_text(...)`
- stop describing audio as an afterthought mux step

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_make_manim_video_scaffold.py -q
```
Expected: pass.

**Step 5: Commit**
```bash
git add scripts/make-manim-video.py tests/test_make_manim_video_scaffold.py
git commit -m "feat: scaffold narrated video manifest artifacts"
```

---

### Task 4: Add per-scene TTS generation to the podcast helper path

**Objective:** Reuse the podcast TTS backend for scene clips, not only whole-show MP3 generation.

**Files:**
- Modify: `scripts/run_podcastfy_pipeline.py`
- Possibly create: `scripts/video_audio_timeline.py`
- Modify: `scripts/podcast_pipeline_common.py`

**Step 1: Write failing tests**
Add tests for:
- converting a list of scene texts into one TTS request per scene
- returning measured clip durations
- refusing empty narration scenes

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 3: Implement scene clip synthesis**
Do one of these cleanly (pick one, document why):
- extend `run_podcastfy_pipeline.py` with a scene-clip mode, or
- keep `run_podcastfy_pipeline.py` for full podcasts and build a new `video_audio_timeline.py` that directly calls the OpenAI-compatible TTS endpoint.

Recommendation: use a new `video_audio_timeline.py` helper so podcast episode assumptions do not leak into the video path.

The helper should:
- read the manifest
- synthesize each scene clip
- measure each with `ffprobe`
- write `audio_clip_path` + `audio_duration_s` back into the manifest

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 5: Commit**
```bash
git add scripts/run_podcastfy_pipeline.py scripts/video_audio_timeline.py scripts/podcast_pipeline_common.py tests/test_video_audio_timeline.py
git commit -m "feat: synthesize per-scene narration clips"
```

---

### Task 5: Implement the overrun-repair ladder

**Objective:** Prevent unnecessary rewrites and preserve good wording when clips slightly miss budget.

**Files:**
- Modify: `scripts/video_audio_timeline.py`
- Modify: `scripts/video_scene_manifest.py`
- Modify: `tests/test_video_audio_timeline.py`

**Step 1: Write failing tests**
Test these ordered repair behaviors:
1. trim filler
2. allow minor `atempo` if <= configured threshold
3. spend pause slack if available
4. mark scene for rewrite when still too long
5. mark scene for duration extension when rewrite is rejected or still too long

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 3: Implement repair ladder**
Add a function like:
```python
def repair_scene_overrun(scene, *, max_atempo: float, available_pause_slack_s: float) -> RepairDecision:
    ...
```

The result should record what happened so the manifest remains auditable.

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 5: Commit**
```bash
git add scripts/video_audio_timeline.py scripts/video_scene_manifest.py tests/test_video_audio_timeline.py
git commit -m "feat: add narrated scene overrun repair ladder"
```

---

### Task 6: Build master narration assembly + loudness normalization

**Objective:** Assemble a clean final audio bed from normalized scene clips.

**Files:**
- Modify: `scripts/video_audio_timeline.py`
- Modify: `tests/test_video_audio_timeline.py`

**Step 1: Write failing tests**
Test:
- silence insertion between scene clips
- frame-snapped offsets
- generation of concat manifest
- inclusion of `loudnorm` step metadata

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 3: Implement assembly**
Use `ffmpeg` to:
- normalize each scene clip to target LUFS
- create silence segments as needed
- assemble one master narration track in timeline order
- write final offsets into the manifest

Do not store redundant `audio_end`; derive it from offset + duration.

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 5: Commit**
```bash
git add scripts/video_audio_timeline.py tests/test_video_audio_timeline.py
git commit -m "feat: assemble normalized narration timeline"
```

---

### Task 7: Make Manim read the manifest

**Objective:** Move timing authority into the manifest so visuals conform to narration.

**Files:**
- Create: `scripts/render_manim_from_manifest.py`
- Modify: `scripts/make-manim-video.py`
- Modify: generated `render.sh` template logic inside `scripts/make-manim-video.py`

**Step 1: Write failing tests**
Test:
- a manifest scene with `scene_duration_s=8.4` yields a render plan with matching holds
- beat anchors become subcaptions or scene annotations

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_scene_manifest.py tests/test_make_manim_video_scaffold.py -q
```

**Step 3: Implement manifest-driven render path**
`render_manim_from_manifest.py` should:
- load the manifest
- generate scene classes or a render plan from it
- ensure hold times and reveal beats conform to `scene_duration_s`
- optionally emit subcaption timing from the same beat metadata

`make-manim-video.py` should emit `render.sh` that calls this helper in narrated mode.

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_scene_manifest.py tests/test_make_manim_video_scaffold.py -q
```

**Step 5: Commit**
```bash
git add scripts/render_manim_from_manifest.py scripts/make-manim-video.py tests/test_video_scene_manifest.py tests/test_make_manim_video_scaffold.py
git commit -m "feat: render manim scenes from narration manifest"
```

---

### Task 8: Derive captions from narration alignment

**Objective:** Stop treating SRT as an unrelated layer.

**Files:**
- Modify: `scripts/video_audio_timeline.py`
- Possibly create: `scripts/video_caption_alignment.py`

**Step 1: Write failing tests**
Test generation of `captions/final.srt` from manifest scenes + narration alignment timestamps.

**Step 2: Run tests to verify failure**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 3: Implement caption generation**
Preferred order:
- if TTS backend returns alignment/word timestamps, use them
- otherwise run forced alignment (`whisperx`, `aeneas`, or another chosen tool) against the scene clips
- emit one final SRT derived from the manifest timeline

**Step 4: Run tests to verify pass**
Run:
```bash
pytest tests/test_video_audio_timeline.py -q
```

**Step 5: Commit**
```bash
git add scripts/video_audio_timeline.py scripts/video_caption_alignment.py tests/test_video_audio_timeline.py
git commit -m "feat: derive explainer captions from narration alignment"
```

---

### Task 9: Final mux + Jellyfin delivery flow

**Objective:** Produce one narrated MP4 from the manifest-driven render + master audio.

**Files:**
- Modify: `scripts/make-manim-video.py`
- Modify: `SETUP.md`

**Step 1: Add final integration commands**
Document and script:
- render silent/manim video from manifest
- build master narration track
- mux final MP4
- archive manifest/narration artifacts
- refresh Jellyfin

**Step 2: Verify integration locally**
Run commands like:
```bash
python3 -m py_compile scripts/make-manim-video.py scripts/video_scene_manifest.py scripts/video_voice_calibration.py scripts/video_audio_timeline.py scripts/render_manim_from_manifest.py
bash -n /opt/hermes/scripts/setup-video-pipeline.sh
```

Then perform one narrated draft render against a small test project.

**Step 3: Commit**
```bash
git add scripts/make-manim-video.py SETUP.md
git commit -m "docs: add manifest-driven narrated explainer flow"
```

---

## 5. Quality Gates

Before calling the refactor done:

1. Silent mode still works without requiring narration artifacts.
2. Narrated mode always produces:
   - `scene_manifest.json`
   - `narration-script.md`
   - per-scene audio clips
   - measured durations in the manifest
   - master narration track
   - final MP4
3. A narrated scene overrun can be repaired without forcing a full rewrite every time.
4. Frame-snapped offsets are respected at the chosen fps.
5. Loudness is normalized scene-to-scene.
6. Captions derive from the same timing source as the narration.
7. Wiki archival includes narration artifacts, not only the brief.
8. Jellyfin delivery still works after final mux.

---

## 6. Explicit Non-Goals

- Do not redesign the podcast episode pipeline around this work.
- Do not require narration for every explainer.
- Do not make Docker the default render path.
- Do not treat one manually tuned sample video as proof of general correctness; build reusable helpers.

---

## 7. Execution Notes

Recommended implementation order:
1. manifest schema
2. voice calibration
3. narrated scaffold output
4. per-scene TTS
5. repair ladder
6. loudnorm + timeline assembly
7. manifest-driven Manim render
8. captions from alignment
9. final mux + docs

After this plan is implemented, update the `video-explainer-pipeline` skill again if any file names, flags, or runtime helpers differ from the plan.
