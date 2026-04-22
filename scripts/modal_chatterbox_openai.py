#!/usr/bin/env python3
"""Modal-hosted OpenAI-compatible Chatterbox TTS endpoint.

Purpose:
- Provide a default serverless TTS backend for the Hermes podcast pipeline.
- Expose OpenAI-compatible speech routes so podcastfy can keep using --tts-model openai.
- Keep the wire contract stable so a future Apple Silicon backend can reuse the same API shape.

Quick start:
- Ensure `modal` is installed locally (`scripts/setup-podcast-pipeline.sh` now installs it in the podcast venv).
- Authenticate once: `modal setup`
- Create/upload optional voice prompts volume:
    modal volume create chatterbox-tts-voices
    modal volume put chatterbox-tts-voices /path/to/prompts
- Create the required Hugging Face secret if model access needs it:
    modal secret create hf-token HF_TOKEN=***
- Deploy:
    /home/hermes/.venvs/podcast-pipeline/bin/python -m modal deploy scripts/modal_chatterbox_openai.py

After deploy, use the returned HTTPS base URL as `TTS_BASE_URL`, for example:
    https://<workspace>--hermes-chatterbox-openai.modal.run

Compatibility routes:
- Bare-root OpenAI client base URL callers will hit: $TTS_BASE_URL/audio/speech
- `/v1`-prefixed OpenAI client base URL callers will hit: $TTS_BASE_URL/v1/audio/speech

Important: MP3 requests now return real MP3 bytes rather than WAV-in-an-.mp3 wrapper.
This keeps podcastfy's merge step compatible with the Modal backend.
"""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import modal

APP_NAME = "hermes-chatterbox-openai"
VOICE_ROOT = "/voices"
DEFAULT_VOICE_FILE = "Lucy.wav"
STRICT_ALIAS_GROUPS = {"female", "male", "shimmer", "nova", "echo", "alloy"}
VOICE_ALIAS_CANDIDATES = {
    "female": ["female.wav", "Female.wav", "Lucy.wav"],
    "shimmer": ["female.wav", "Female.wav", "Lucy.wav", "shimmer.wav", "Shimmer.wav"],
    "nova": ["female.wav", "Female.wav", "Lucy.wav", "nova.wav", "Nova.wav"],
    "male": ["male.wav", "Male.wav", "Adam.wav", "adam.wav"],
    "echo": ["male.wav", "Male.wav", "Adam.wav", "adam.wav", "echo.wav", "Echo.wav"],
    "alloy": ["male.wav", "Male.wav", "Adam.wav", "adam.wav", "alloy.wav", "Alloy.wav"],
}

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg")
    .uv_pip_install(
        "chatterbox-tts==0.1.6",
        "fastapi[standard]==0.124.4",
        "numpy<2",
        "peft==0.18.0",
        "soundfile==0.13.1",
    )
)

voice_prompts = modal.Volume.from_name("chatterbox-tts-voices", create_if_missing=True)
app = modal.App(APP_NAME, image=image)

with image.imports():
    from chatterbox.tts_turbo import ChatterboxTurboTTS
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import JSONResponse, Response

    MODEL = None


def voice_search_roots() -> list[Path]:
    return [
        Path(VOICE_ROOT),
        Path(VOICE_ROOT) / "chatterbox-tts-voices" / "prompts",
    ]


def available_prompt_files() -> list[str]:
    prompts: list[str] = []
    seen: set[str] = set()
    for root in voice_search_roots():
        if not root.exists():
            continue
        for candidate in sorted(root.glob("*.wav")):
            if candidate.name in seen:
                continue
            prompts.append(str(candidate))
            seen.add(candidate.name)
    return prompts


def resolve_voice_prompt(voice_name: str | None) -> dict[str, object]:
    requested = (voice_name or "Lucy").strip() or "Lucy"
    requested_lower = requested.lower()

    filename_candidates = VOICE_ALIAS_CANDIDATES.get(requested_lower)
    resolution = "exact"
    if filename_candidates:
        resolution = requested_lower
    else:
        filename_candidates = [requested if requested_lower.endswith(".wav") else f"{requested}.wav"]

    for filename in filename_candidates:
        for root in voice_search_roots():
            candidate = root / filename
            if candidate.exists():
                return {
                    "requested_voice": requested,
                    "resolution": resolution,
                    "candidate_files": filename_candidates,
                    "resolved_prompt": str(candidate),
                    "used_fallback": False,
                    "error": None,
                }

    if requested_lower in STRICT_ALIAS_GROUPS:
        canonical_target = "female.wav" if requested_lower in {"female", "shimmer", "nova"} else "male.wav"
        return {
            "requested_voice": requested,
            "resolution": resolution,
            "candidate_files": filename_candidates,
            "resolved_prompt": None,
            "used_fallback": False,
            "error": (
                f"Voice alias '{requested}' requires a distinct prompt file. "
                f"Upload one of {filename_candidates} to the Modal volume (canonical target: {canonical_target})."
            ),
        }

    for root in voice_search_roots():
        fallback = root / DEFAULT_VOICE_FILE
        if fallback.exists():
            return {
                "requested_voice": requested,
                "resolution": "fallback",
                "candidate_files": filename_candidates,
                "resolved_prompt": str(fallback),
                "used_fallback": True,
                "error": None,
            }

    return {
        "requested_voice": requested,
        "resolution": resolution,
        "candidate_files": filename_candidates,
        "resolved_prompt": None,
        "used_fallback": False,
        "error": f"No voice prompt files found under {VOICE_ROOT}",
    }


def file_sha256(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def inspect_prompt_file(path_str: str | None, target_sr: int | None = None) -> dict[str, object]:
    info: dict[str, object] = {
        "path": path_str,
        "exists": False,
        "size_bytes": None,
        "sha256": None,
        "target_sr": target_sr,
        "librosa_native": None,
        "librosa_target": None,
        "soundfile": None,
        "error": None,
    }
    if not path_str:
        info["error"] = "No prompt path provided"
        return info

    path = Path(path_str)
    if not path.exists():
        info["error"] = "Prompt path does not exist"
        return info

    info["exists"] = True
    info["size_bytes"] = path.stat().st_size
    info["sha256"] = file_sha256(path)

    try:
        import soundfile as sf

        sf_info = sf.info(str(path))
        info["soundfile"] = {
            "samplerate": sf_info.samplerate,
            "frames": sf_info.frames,
            "channels": sf_info.channels,
            "duration_seconds": sf_info.duration,
            "format": sf_info.format,
            "subtype": sf_info.subtype,
        }
    except Exception as exc:
        info["soundfile"] = {"error": repr(exc)}

    try:
        import librosa

        native_wav, native_sr = librosa.load(str(path), sr=None)
        info["librosa_native"] = {
            "sr": native_sr,
            "num_samples": int(len(native_wav)),
            "duration_seconds": float(len(native_wav) / native_sr) if native_sr else None,
        }
        if target_sr:
            target_wav, actual_sr = librosa.load(str(path), sr=target_sr)
            info["librosa_target"] = {
                "sr": actual_sr,
                "num_samples": int(len(target_wav)),
                "duration_seconds": float(len(target_wav) / actual_sr) if actual_sr else None,
            }
    except Exception as exc:
        info["error"] = repr(exc)

    return info


def render_audio_bytes(samples, sample_rate: int, response_format: str) -> tuple[bytes, str]:
    import wave

    import numpy as np

    pcm16 = np.clip(samples, -1.0, 1.0)
    pcm16 = (pcm16 * 32767.0).astype(np.int16)
    pcm_bytes = pcm16.tobytes()

    if response_format == "pcm":
        return pcm_bytes, "application/octet-stream"

    wav_buffer = io.BytesIO()
    with wave.open(wav_buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm_bytes)
    wav_bytes = wav_buffer.getvalue()

    if response_format == "wav":
        return wav_bytes, "audio/wav"

    ffmpeg = subprocess.run(
        [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "wav",
            "-i",
            "pipe:0",
            "-f",
            "mp3",
            "-codec:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "pipe:1",
        ],
        input=wav_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if ffmpeg.returncode != 0:
        detail = ffmpeg.stderr.decode("utf-8", errors="replace").strip() or "ffmpeg mp3 encode failed"
        raise RuntimeError(detail)
    return ffmpeg.stdout, "audio/mpeg"


@app.function(
    gpu="a10g",
    scaledown_window=60 * 5,
    timeout=60 * 15,
    secrets=[modal.Secret.from_name("hf-token")],
    volumes={VOICE_ROOT: voice_prompts},
)
@modal.asgi_app()
def fastapi_app():
    startup_time = datetime.now(timezone.utc).isoformat()
    app_version = os.getenv("HERMES_CHATTERBOX_APP_VERSION", "dev")

    web_app = FastAPI(
        title="Hermes Chatterbox OpenAI API",
        description="OpenAI-compatible text-to-speech API backed by Chatterbox Turbo on Modal.",
        version="0.1.0",
    )

    @web_app.on_event("startup")
    def startup() -> None:
        global MODEL
        if MODEL is None:
            MODEL = ChatterboxTurboTTS.from_pretrained(device="cuda")

    @web_app.get("/health")
    def health() -> JSONResponse:
        global MODEL
        voice_debug = {
            alias: resolve_voice_prompt(alias)
            for alias in ["female", "male", "shimmer", "nova", "echo", "alloy", "Lucy", "Adam"]
        }
        prompt_inspection = {
            alias: inspect_prompt_file(
                str(details.get("resolved_prompt") or ""),
                getattr(MODEL, "sr", None),
            )
            for alias, details in voice_debug.items()
        }
        return JSONResponse(
            {
                "ok": True,
                "model_loaded": MODEL is not None,
                "app_version": app_version,
                "startup_time": startup_time,
                "default_voice_prompt": resolve_voice_prompt("Lucy").get("resolved_prompt"),
                "speech_endpoints": ["/audio/speech", "/v1/audio/speech"],
                "default_response_format": "mp3",
                "supported_response_formats": ["mp3", "wav", "pcm"],
                "available_prompt_files": available_prompt_files(),
                "voice_alias_candidates": VOICE_ALIAS_CANDIDATES,
                "voice_debug": voice_debug,
                "prompt_inspection": prompt_inspection,
            }
        )

    @web_app.get("/debug/prompt/{voice_name}")
    def debug_prompt(voice_name: str) -> JSONResponse:
        global MODEL
        resolution = resolve_voice_prompt(voice_name)
        prompt_path = str(resolution.get("resolved_prompt") or "")
        return JSONResponse(
            {
                "ok": True,
                "app_version": app_version,
                "startup_time": startup_time,
                "model_loaded": MODEL is not None,
                "requested_voice": voice_name,
                "resolution": resolution,
                "available_prompt_files": available_prompt_files(),
                "prompt_inspection": inspect_prompt_file(prompt_path, getattr(MODEL, "sr", None)),
            }
        )

    def create_speech_impl(payload: dict) -> Response:
        global MODEL
        if MODEL is None:
            raise HTTPException(status_code=503, detail="Model is still loading")

        input_text = str(payload.get("input", "")).strip()
        if not input_text:
            raise HTTPException(status_code=400, detail="Missing required field: input")

        response_format = str(payload.get("response_format", "mp3")).lower()
        if response_format not in {"wav", "pcm", "mp3"}:
            raise HTTPException(status_code=400, detail="Supported response_format values: wav, pcm, mp3")

        resolution = resolve_voice_prompt(payload.get("voice", "Lucy"))
        if resolution.get("error"):
            raise HTTPException(status_code=503, detail=str(resolution["error"]))
        voice_prompt = str(resolution.get("resolved_prompt") or "")
        prompt_debug = inspect_prompt_file(voice_prompt, getattr(MODEL, "sr", None))
        print(
            "speech_request_debug",
            {
                "app_version": app_version,
                "requested_voice": resolution.get("requested_voice"),
                "resolution": resolution.get("resolution"),
                "voice_prompt": voice_prompt,
                "prompt_debug": prompt_debug,
            },
            flush=True,
        )
        try:
            waveform = MODEL.generate(input_text, audio_prompt_path=voice_prompt)
        except Exception as exc:
            raise HTTPException(
                status_code=500,
                detail={
                    "error": repr(exc),
                    "app_version": app_version,
                    "requested_voice": resolution.get("requested_voice"),
                    "resolution": resolution.get("resolution"),
                    "voice_prompt": voice_prompt,
                    "prompt_debug": prompt_debug,
                },
            ) from exc
        samples = waveform.squeeze().detach().cpu().numpy()

        try:
            rendered_bytes, media_type = render_audio_bytes(samples, MODEL.sr, response_format)
        except RuntimeError as exc:
            raise HTTPException(status_code=500, detail=f"Audio encode failed: {exc}") from exc

        return Response(
            content=rendered_bytes,
            media_type=media_type,
            headers={
                "x-tts-backend": "chatterbox-turbo",
                "x-voice-requested": str(resolution.get("requested_voice") or ""),
                "x-voice-resolution": str(resolution.get("resolution") or ""),
                "x-voice-prompt": voice_prompt or "none",
                "x-voice-fallback": str(bool(resolution.get("used_fallback"))).lower(),
                "x-response-format": response_format,
            },
        )

    @web_app.post("/v1/audio/speech")
    def create_speech_v1(payload: dict) -> Response:
        return create_speech_impl(payload)

    @web_app.post("/audio/speech")
    def create_speech_root(payload: dict) -> Response:
        return create_speech_impl(payload)

    return web_app


@app.local_entrypoint()
def main(prompt: str = "Hermes podcast pipeline speaking through Modal [chuckle]."):
    print("Deploy with:")
    print("  python -m modal deploy scripts/modal_chatterbox_openai.py")
    print()
    print("Then set one of:")
    print("  export TTS_BASE_URL=https://<workspace>--hermes-chatterbox-openai.modal.run")
    print("  export CHATTERBOX_BASE_URL=https://<workspace>--hermes-chatterbox-openai.modal.run")
    print()
    print("Health endpoint:")
    print("  $TTS_BASE_URL/health")
    print()
    print("Speech endpoint:")
    print("  $TTS_BASE_URL/v1/audio/speech")
    print()
    print(f"Suggested smoke-test prompt: {prompt}")
