#!/usr/bin/env python3
"""Modal-hosted OpenAI-compatible Chatterbox TTS endpoint.

Purpose:
- Provide a default serverless TTS backend for the Hermes podcast pipeline.
- Expose POST /v1/audio/speech so podcastfy can keep using --tts-model openai.
- Keep the wire contract stable so a future Apple Silicon backend can reuse the same API shape.

Quick start:
- Ensure `modal` is installed locally (`scripts/setup-podcast-pipeline.sh` now installs it in the podcast venv).
- Authenticate once: `modal setup`
- Create/upload optional voice prompts volume:
    modal volume create chatterbox-tts-voices
    modal volume put chatterbox-tts-voices /path/to/prompts
- Create the required Hugging Face secret if model access needs it:
    modal secret create hf-token HF_TOKEN=hf_xxx
- Deploy:
    /home/hermes/.venvs/podcast-pipeline/bin/python -m modal deploy scripts/modal_chatterbox_openai.py

After deploy, use the returned HTTPS base URL as `TTS_BASE_URL`, for example:
    https://<workspace>--hermes-chatterbox-openai.modal.run

The podcast pipeline expects the OpenAI-compatible speech endpoint at:
    $TTS_BASE_URL/v1/audio/speech
"""

from __future__ import annotations

import modal

APP_NAME = "hermes-chatterbox-openai"
VOICE_ROOT = "/voices"
DEFAULT_VOICE_FILE = "Lucy.wav"

image = modal.Image.debian_slim(python_version="3.11").uv_pip_install(
    "chatterbox-tts==0.1.6",
    "fastapi[standard]==0.124.4",
    "numpy<2",
    "peft==0.18.0",
    "soundfile==0.13.1",
)

voice_prompts = modal.Volume.from_name("chatterbox-tts-voices", create_if_missing=True)
app = modal.App(APP_NAME, image=image)

with image.imports():
    import io
    from pathlib import Path

    import soundfile as sf
    from chatterbox.tts_turbo import ChatterboxTurboTTS
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import JSONResponse, Response

    MODEL = None


def resolve_voice_prompt(voice_name: str | None) -> str | None:
    if not voice_name:
        voice_name = "Lucy"

    requested = voice_name.strip()
    if not requested:
        requested = "Lucy"
    filename = requested if requested.lower().endswith(".wav") else f"{requested}.wav"

    direct = Path(VOICE_ROOT) / filename
    if direct.exists():
        return str(direct)

    nested = Path(VOICE_ROOT) / "chatterbox-tts-voices" / "prompts" / filename
    if nested.exists():
        return str(nested)

    fallback = Path(VOICE_ROOT) / "chatterbox-tts-voices" / "prompts" / DEFAULT_VOICE_FILE
    if fallback.exists():
        return str(fallback)

    return None


@app.function(
    gpu="a10g",
    scaledown_window=60 * 5,
    timeout=60 * 15,
    secrets=[modal.Secret.from_name("hf-token")],
    volumes={VOICE_ROOT: voice_prompts},
)
@modal.asgi_app()
def fastapi_app():
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
        return JSONResponse(
            {
                "ok": True,
                "model_loaded": MODEL is not None,
                "default_voice_prompt": resolve_voice_prompt("Lucy"),
                "speech_endpoint": "/v1/audio/speech",
            }
        )

    @web_app.post("/v1/audio/speech")
    def create_speech(payload: dict) -> Response:
        global MODEL
        if MODEL is None:
            raise HTTPException(status_code=503, detail="Model is still loading")

        input_text = str(payload.get("input", "")).strip()
        if not input_text:
            raise HTTPException(status_code=400, detail="Missing required field: input")

        response_format = str(payload.get("response_format", "wav")).lower()
        if response_format not in {"wav", "pcm", "mp3"}:
            raise HTTPException(status_code=400, detail="Supported response_format values: wav, pcm, mp3")

        voice_prompt = resolve_voice_prompt(payload.get("voice", "Lucy"))
        waveform = MODEL.generate(input_text, audio_prompt_path=voice_prompt)
        samples = waveform.squeeze().detach().cpu().numpy()

        buffer = io.BytesIO()
        if response_format == "pcm":
            sf.write(buffer, samples, MODEL.sr, format="RAW", subtype="PCM_16")
            media_type = "application/octet-stream"
        else:
            # Return WAV bytes for both wav and mp3 requests by default. This keeps the
            # endpoint useful to OpenAI-compatible clients without adding ffmpeg/lame
            # encoding complexity inside the serverless image.
            sf.write(buffer, samples, MODEL.sr, format="WAV")
            media_type = "audio/wav"

        return Response(
            content=buffer.getvalue(),
            media_type=media_type,
            headers={
                "x-tts-backend": "chatterbox-turbo",
                "x-voice-prompt": voice_prompt or "none",
                "x-response-format": response_format,
            },
        )

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
