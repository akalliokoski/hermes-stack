---
name: podcast-pipeline
description: Generate two-host podcasts on the VPS with Hermes + podcastfy, route TTS to a Modal serverless Chatterbox endpoint by default, optionally support a future Apple Silicon backend over Tailscale/local, write MP3s into Audiobookshelf, optionally mirror with Syncthing, and notify via Hermes.
---

# Podcast Pipeline: podcastfy + Modal Chatterbox → iPhone + Apple Watch

Use this skill when the user wants Hermes to turn source material into a podcast episode that can be delivered through Audiobookshelf to iPhone and Apple Watch.

This is a shared cross-profile skill. Any profile can use it because it lives in the global skills directory.

## Architecture

- VPS responsibilities:
  - Hermes orchestrates the job.
  - Hermes extracts source content.
  - Hermes generates, revises, validates, audits, and archives a canonical structured transcript JSON artifact.
  - Hermes renders that canonical transcript into Podcastfy-compatible dialogue for the current audio path.
  - `podcastfy` assembles the final audio.
  - Output MP3 is written to `/data/audiobookshelf/podcasts/ai-generated/`.
  - Hermes triggers an Audiobookshelf library scan and sends a notification.
- Default TTS backend:
  - Modal runs Chatterbox as a serverless TTS service.
  - Expose an OpenAI-compatible `/v1/audio/speech` style endpoint from Modal so `podcastfy` can keep using `--tts-model openai`.
  - Hermes/podcastfy calls the deployed Modal URL via `OPENAI_BASE_URL`.
- Optional future TTS backend:
  - A local Apple Silicon model can expose the same OpenAI-compatible interface.
  - Hermes should be able to swap the base URL to a local or Tailscale-reachable host without changing the rest of the pipeline.
- Delivery:
  - Audiobookshelf serves the MP3 to iPhone.
  - Plappa on Apple Watch downloads episodes for offline playback.
  - Syncthing can mirror generated files to the Mac.

## Key decisions

1. Chatterbox running on Modal serverless is the default TTS backend.
2. Hermes generates the transcript; podcastfy should not do the LLM step.
3. TTS integration stays OpenAI-compatible so the backend can later move to Apple Silicon locally or over Tailscale.
4. Plappa is the preferred Apple Watch client.
5. Hermes sends the final ready notification.
6. Canonical structured transcript JSON is the only accepted transcript input; legacy raw `HOST_A:` / `HOST_B:` transcript text must hard-fail.
7. Output filenames should be order-first and come directly from canonical `episode_slug` with no auto-prepended date.
8. Every podcast transcript should also be archived into the shared wiki under `raw/transcripts/media/podcasts/` so it is easy to find later.
9. Audiobookshelf is the media server on the VPS.

## Required environment / configuration

Before running the pipeline, confirm these values:

- Modal app URL for the deployed Chatterbox endpoint, for example:
  - `https://<workspace>--<app-name>.modal.run`
- Optional future Apple Silicon fallback URL, for example:
  - `http://100.x.y.z:8880/v1`
  - or `http://mac-hostname.tailnet-name.ts.net:8880/v1`
  - or a local loopback URL when Hermes runs on the same Mac
- Audiobookshelf base URL, for example:
  - `http://127.0.0.1:13378` from the VPS itself
  - `https://<current-tailscale-node-name>.<your-tailnet>.ts.net:13378` from tailnet devices
- Audiobookshelf API token, or admin username/password for login-based helpers
- Existing output directory root:
  - `/data/audiobookshelf/podcasts/ai-generated/`
  - the pipeline writes each generated episode under its own show subdirectory, e.g. `/data/audiobookshelf/podcasts/ai-generated/<show-slug>/YYYY-MM-DD_<slug>.mp3`
- `podcastfy` installed on the VPS
- A reachable OpenAI-compatible TTS endpoint backed by Chatterbox (Modal by default)

Recommended environment variables:

- `TTS_BASE_URL` or `CHATTERBOX_BASE_URL`
- `AUDIOBOOKSHELF_BASE_URL`
- `AUDIOBOOKSHELF_TOKEN`
- `PODCAST_OUTPUT_DIR=/data/audiobookshelf/podcasts/ai-generated`
- optional legacy compatibility: `KOKORO_BASE_URL`

Operational note:
- if you run the repo helpers from a plain terminal context, do not assume Hermes chat secrets are automatically present in that shell.
- for Audiobookshelf scan/verification to work non-interactively, ensure `AUDIOBOOKSHELF_TOKEN` (or admin username/password fallback) is exported into the shell or stored in an env file that the helper actually loads, such as `/home/hermes/.hermes/.env`.
- otherwise audio generation can still succeed, but the Audiobookshelf scan step may be skipped best-effort.

## Directory layout

Keep the skill intentionally thin. Runtime logic should live in `hermes-stack`, not inside the skill directory.

Canonical repo tools:

```text
/opt/hermes/scripts/make-podcast.py
/opt/hermes/scripts/run_podcastfy_pipeline.py
/opt/hermes/scripts/audiobookshelf_api.py
/opt/hermes/scripts/bootstrap-audiobookshelf.py
/opt/hermes/scripts/modal_chatterbox_openai.py
/opt/hermes/scripts/sync-modal-hf-secret.py
```

Shared transcript archive root:

```text
/opt/hermes/wiki/raw/transcripts/media/podcasts/
```

The skill should provide prompting/orchestration guidance only. If runtime behavior changes, prefer patching the repo tools and then updating this skill's documentation to match.

## Source ingestion workflow

Hermes should do ingestion first, then transcript generation, then audio assembly.

Supported sources in the plan:
- URLs
- PDFs
- YouTube
- Direct pasted notes/text

Preferred extraction flow:
1. Use Hermes tools to fetch or extract content.
2. Normalize into a single source packet.
3. Generate canonical transcript JSON in two passes:
   - draft JSON
   - revision JSON
4. Validate the transcript schema and run a local transcript audit.
5. Render the canonical transcript into Podcastfy's expected format:

```text
<Person1>...</Person1>
<Person2>...</Person2>
<Person1>...</Person1>
```

6. Archive structured transcript JSON, audit JSON, and rendered transcript text into the shared wiki.
7. Hand the rendered transcript to `podcastfy` for audio synthesis.

Important: validated against `podcastfy==0.4.3` — the TTS pipeline expects `Person1`/`Person2`-style dialogue, not canonical `HOST_A`/`HOST_B` speaker labels directly.

Important: bypass podcastfy's internal LLM call. Hermes owns transcript generation.

## Naming convention

Output file format:

```text
<episode-slug>.mp3
```

Examples:

```text
phase-00.1-01trajectory-anomaly-detection.mp3
phase-00.1-02dataset-construction-and-anomaly-taxonomy.mp3
```

Use the canonical transcript `episode_slug` directly so Audiobookshelf and playlists sort by learning-plan order rather than by generation date.

## Orchestration steps

Repo helper for terminal/Hermes execution:
- `/opt/hermes/scripts/make-podcast.py`
- `/opt/hermes/scripts/setup-podcast-pipeline.sh`
- `/opt/hermes/scripts/modal_chatterbox_openai.py`

In the hermes-stack deployment, `setup-podcast-pipeline.sh` provisions a dedicated venv at:
- `/home/hermes/.venvs/podcast-pipeline/bin/python`

That venv should include both `podcastfy` and `modal` so Hermes can deploy the default Modal backend directly from chat on the VPS.

`make-podcast.py` is the validated end-to-end wrapper. It can:
- call Hermes itself to generate a structured transcript from local files, URLs, inline text, or a topic hint
- run a two-pass transcript flow (draft JSON -> revision JSON)
- validate and audit the canonical transcript locally
- archive structured transcript JSON, audit JSON, and rendered transcript text into the shared wiki under `raw/transcripts/media/podcasts/`
- accept `--transcript` only as canonical transcript JSON and hard-fail legacy raw transcript text
- invoke the repo `run_podcastfy_pipeline.py` helper for podcastfy
- write the final MP3 into `/data/audiobookshelf/podcasts/ai-generated/`
- trigger an Audiobookshelf scan
- send a Telegram ready notification when Telegram env is configured

Implementation findings worth preserving:
- validate canonical transcript JSON before rendering it for Podcastfy so all structured-input paths share one contract
- `--dry-run` should still emit transcript artifacts and audit output even when no TTS base URL is configured, then skip audio synthesis cleanly
- keep the rendered archive semantic honest: if input is canonical JSON, archive rendered `<Person1>/<Person2>` dialogue rather than raw JSON under the rendered-transcript artifact label

When asked to make a podcast:

1. Collect and extract source material.
2. Build a source packet.
3. Ask Hermes for draft canonical transcript JSON.
4. Ask Hermes for revised canonical transcript JSON.
5. Validate and audit the transcript locally.
6. Render the canonical transcript into Podcastfy-compatible dialogue.
7. Run the pipeline with `podcastfy`, configured for OpenAI-compatible TTS.
8. Point `OPENAI_BASE_URL` at the Modal Chatterbox deployment by default.
9. If needed later, swap `OPENAI_BASE_URL` to a local Apple Silicon endpoint exposed locally or over Tailscale.
10. Write the final MP3 into `/data/audiobookshelf/podcasts/ai-generated/`.
11. Trigger Audiobookshelf scan through its REST API.
12. Notify the user that the episode is ready.

## podcastfy configuration pattern

Validated against `podcastfy==0.4.3`:

- invoke it as `python -m podcastfy.client`
- use `--transcript <file>` and `--tts-model openai`
- there is no validated `--output` flag in this version; control output via a temporary conversation config and rename the emitted MP3 afterward
- redirect OpenAI-compatible TTS traffic by setting environment variable `OPENAI_BASE_URL=<deployed-modal-or-local-backend>/v1`
- default target is a Modal serverless Chatterbox deployment
- keep the integration backend-agnostic so a future Apple Silicon service can be swapped in by changing only the base URL
- set `OPENAI_API_KEY` to a dummy non-empty value if the upstream service does not require auth, because podcastfy still insists on an OpenAI API key being present

Important validation note:
- the installed CLI's `--help` path is currently noisy/brittle because of a Typer incompatibility, but the command itself still loads and the option definitions in `podcastfy.client` confirm `--transcript` and `--tts-model`
- `podcastfy` 0.4.3 uses `text_to_speech.openai.default_voices.question` and `.answer` for alternating two-host output, so keep Person1/HOST_A mapped to the female alias and Person2/HOST_B mapped to the male alias.

## Modal setup notes for Chatterbox

Use the `modal-serverless-gpu` skill for deployment details.

Expected default setup:

- Modal app hosts Chatterbox behind an OpenAI-compatible FastAPI endpoint.
- Deploy with `modal deploy <app>.py` and capture the generated HTTPS URL.
- Prefer an API shape compatible with OpenAI speech generation so `podcastfy` can continue using `--tts-model openai` unchanged.
- Create a Modal secret named `hf-token` with `HF_TOKEN=...` before deploy if model download requires Hugging Face auth.
- Preferred workflow: keep `HF_TOKEN` in the main Hermes `.env`, then run `python3 /opt/hermes/scripts/sync-modal-hf-secret.py` to copy it into Modal's remote secret store.
- Create a Modal volume named `chatterbox-tts-voices` and upload a default prompt voice such as `Lucy.wav` under `/chatterbox-tts-voices/prompts/Lucy.wav`.
- For deterministic two-host output, also upload canonical prompt files:
  - `/chatterbox-tts-voices/prompts/female.wav`
  - `/chatterbox-tts-voices/prompts/male.wav`
- Keep the returned base URL in `TTS_BASE_URL` or `CHATTERBOX_BASE_URL`.
- Verify `/health` after deploy; if `default_voice_prompt` is `null`, the backend is live but no default prompt voice has been uploaded yet.
- Verify `/health` also exposes `available_prompt_files` and `voice_debug`, and confirm:
  - `shimmer` / `female` resolve to `female.wav`
  - `echo` / `male` resolve to `male.wav`
- Chatterbox prompt WAVs must be longer than 5 seconds; shorter prompts fail live synthesis with `AssertionError: Audio prompt must be longer than 5 seconds!`.

Recommended implementation pattern:
- Use `modal.Image.debian_slim()` with required Python deps for Chatterbox and audio encoding.
- Use a `modal.App` with an ASGI/FastAPI endpoint if you need full OpenAI-compatible request/response handling.
- In hermes-stack, the concrete repo helper is `/opt/hermes/scripts/modal_chatterbox_openai.py`.
- If Chatterbox needs model weights or prompt voices, cache them with a Modal `Volume` to reduce cold-start cost.
- Create the prompt volume with `python -m modal volume create chatterbox-tts-voices`.
- Upload a default prompt voice such as `Lucy.wav` with `python -m modal volume put chatterbox-tts-voices /path/to/Lucy.wav /chatterbox-tts-voices/prompts/Lucy.wav`.
- Verify the live deployment with `/health`; a healthy prompt-backed deploy reports `default_voice_prompt` instead of `null`.
- Modal web endpoint URLs may include the function suffix, e.g. `https://<workspace>--hermes-chatterbox-openai-fastapi-app.modal.run`.
- If startup latency matters, use warm-container settings such as a 5-minute scaledown window.

## Optional future Apple Silicon backend

Later, a local model on Apple Silicon can be exposed with the same OpenAI-compatible interface.

Preferred future shape:
- run locally when Hermes is on the same Mac, or expose it over Tailscale when Hermes runs remotely
- keep the wire contract the same so only `TTS_BASE_URL` changes
- treat this as a backend swap, not a pipeline redesign

## Audiobookshelf integration

- Audiobookshelf watches `/data/audiobookshelf/podcasts/`
- Generated episodes should land in:
  - `/data/audiobookshelf/podcasts/ai-generated/`
- After writing a file, trigger a library scan via REST so the episode appears immediately.

Validated Audiobookshelf API endpoints:
- `POST /login`
- `GET /api/libraries`
- `POST /api/libraries`
- `POST /api/libraries/<ID>/scan?force=1`
- `GET /api/libraries/<ID>/items`
- `GET /api/libraries/<ID>/stats`
- `GET /api/libraries/<ID>/recent-episodes`

Use the helper in `scripts/audiobookshelf_api.py` for:
- logging in with token or admin credentials
- on the VPS, falling back to the local Audiobookshelf SQLite user token cache when explicit auth env vars are absent
- ensuring the podcast library exists
- triggering a scan
- listing recent episodes

Important verification lesson from live testing:
- for locally added test audio, `recent-episodes` may remain empty even when the library scan succeeded
- use `GET /api/libraries/<ID>/items` and/or `GET /api/libraries/<ID>/stats` to verify ingestion after a scan
- for a simple manually added podcast test item, placing an MP3 inside its own show directory under `/data/audiobookshelf/podcasts/ai-generated/<show-name>/` works well; Audiobookshelf ingests the directory as a podcast with one episode

## Syncthing integration

Optional but recommended:

A. Mirror generated podcasts from VPS to Mac
- Sync `/data/audiobookshelf/podcasts/ai-generated/` to the Mac
- Good for Finder browsing and local redundancy

B. Alternative generation flow from Mac
- Generate locally on the Mac
- Drop MP3s into the synced folder
- Let Syncthing deliver them into the VPS Audiobookshelf watched folder

## Notification pattern

After the scan succeeds, Hermes should send a message like:

```text
🎙️ Podcast ready: <title> (<duration>)
Open Plappa or Audiobookshelf to listen.
```

## Repo helper scripts

Treat these as the source of truth for runtime behavior:

- `scripts/make-podcast.py`
  - top-level orchestration
  - optional transcript generation via Hermes
  - writes the final MP3 into `/data/audiobookshelf/podcasts/ai-generated/`
  - triggers an Audiobookshelf scan best-effort
  - sends a Telegram ready notification when configured
- `scripts/run_podcastfy_pipeline.py`
  - normalizes transcript tags
  - configures `podcastfy` for OpenAI-compatible TTS
  - renames the emitted random MP3 to the final `YYYY-MM-DD_<slug>.mp3`
- `scripts/audiobookshelf_api.py`
  - reusable REST helper for login, library ensure/scan, and verification commands
- `scripts/modal_chatterbox_openai.py`
  - deployable Modal OpenAI-compatible Chatterbox backend
- `scripts/sync-modal-hf-secret.py`
  - syncs `HF_TOKEN` from the main Hermes env into the Modal `hf-token` secret

Keep any future skill-side code as thin wrappers or references only; prefer real logic in the repo scripts above.

## Pitfalls

- Do not bake Modal-specific assumptions into the rest of the pipeline beyond the TTS base URL.
- Do not rely on podcastfy's built-in LLM path for transcript generation.
- `podcastfy==0.4.3` does not expose a validated direct output-path flag; expect to rename the generated file after the run.
- `podcastfy` TTS expects `Person1`/`Person2` tags, so raw `HOST_A`/`HOST_B` transcripts must be normalized first.
- `OPENAI_BASE_URL` is the validated way to redirect OpenAI-compatible TTS traffic in the current dependency stack.
- Current repo helper behavior (validated live on 2026-04-19): `scripts/modal_chatterbox_openai.py` now serves both `/audio/speech` and `/v1/audio/speech`, and returns real MP3 bytes for default/mp3 requests. For this helper specifically, the bare Modal app URL works as `TTS_BASE_URL` / `CHATTERBOX_BASE_URL`.
- If you point the pipeline at some other OpenAI-compatible speech server, verify whether its expected base URL already includes `/v1`.
- Modal cold starts may add latency; use warm-container settings only if the latency/cost tradeoff is worth it.
- In the hermes-stack podcast venv, `modal` 1.4.2 broke with `click` 8.3.x (`TypeError: Secondary flag is not valid for non-boolean flag`). Pin `click<8.2` in `scripts/setup-podcast-pipeline.sh` before using `python -m modal setup` or `deploy` there.
- If you later add an Apple Silicon backend, keep the API surface OpenAI-compatible so the pipeline does not fork.
- In hermes-stack, make Audiobookshelf scan best-effort rather than hard-failing the whole pipeline; missing ABS auth/init should not discard a successfully generated MP3.
- Ensure the output directory is writable by the process running Hermes/podcastfy.
- If Audiobookshelf does not detect the file, verify the library path and trigger a manual scan.
- If TTS fails, confirm the deployed backend is reachable and returning OpenAI-compatible responses.

## Verification checklist

Before claiming success:

1. Confirm the Modal Chatterbox endpoint responds over HTTPS.
2. If testing a future local fallback, confirm the Apple Silicon endpoint responds locally or over Tailscale.
3. Confirm `podcastfy` is installed and inspect its help/version.
4. Confirm `/data/audiobookshelf/podcasts/ai-generated/` exists.
5. Generate one test MP3.
6. Trigger Audiobookshelf scan.
7. Verify the episode appears in recent items.
8. Send the user the final ready notification.

## Full flow summary

```text
User asks Hermes for a podcast
→ Hermes extracts and normalizes sources
→ Hermes generates HOST_A/HOST_B transcript
→ podcastfy calls Modal-hosted Chatterbox through an OpenAI-compatible endpoint
→ MP3 written to /data/audiobookshelf/podcasts/ai-generated/
→ Syncthing optionally mirrors to Mac
→ Audiobookshelf scan runs
→ iPhone ABS app and Plappa can access the episode
→ Hermes sends ready notification
```

If a local Apple Silicon backend is added later, only the TTS endpoint changes; the rest of the flow stays the same.
