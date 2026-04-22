from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ALLOWED_CHATTERBOX_TAGS = {"laugh", "chuckle", "sigh", "gasp", "cough"}
CANONICAL_SPEAKERS = {"HOST_A", "HOST_B"}
INLINE_TAG_PATTERN = re.compile(r"\[([a-z]+)\]")
BRACKET_TOKEN_PATTERN = re.compile(r"\[([^\]]+)\]")
TITLE_SLUG_PATTERN = re.compile(r"[^a-z0-9]+")
MAX_EMOTION = 2.0


def extract_inline_tags(text: str) -> list[str]:
    if not isinstance(text, str):
        raise ValueError("turn text must be a string")
    return [match.group(1) for match in INLINE_TAG_PATTERN.finditer(text)]


def extract_bracket_tokens(text: str) -> list[str]:
    if not isinstance(text, str):
        raise ValueError("turn text must be a string")
    return [match.group(1) for match in BRACKET_TOKEN_PATTERN.finditer(text)]


def episode_slug_for_title(title: str) -> str:
    if not isinstance(title, str) or not title.strip():
        raise ValueError("title must be a non-empty string")
    slug = TITLE_SLUG_PATTERN.sub("-", title.strip().lower()).strip("-")
    if not slug:
        raise ValueError("title does not contain slug-safe characters")
    return slug


def _require_mapping(name: str, value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be an object")
    return value


def _require_non_empty_string(name: str, value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string")
    return value.strip()


def _validate_emotion(value: Any, *, field_name: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise ValueError(f"{field_name} must be numeric")
    numeric = float(value)
    if numeric < 0.0 or numeric > MAX_EMOTION:
        raise ValueError(f"{field_name} must be between 0.0 and {MAX_EMOTION}")
    return numeric


def validate_transcript(data: Any) -> dict[str, Any]:
    transcript = _require_mapping("transcript", data)
    version = transcript.get("version")
    if version != 1:
        raise ValueError("transcript.version must equal 1")
    _require_non_empty_string("transcript.title", transcript.get("title"))
    _require_non_empty_string("transcript.episode_slug", transcript.get("episode_slug"))
    _require_non_empty_string("transcript.show_slug", transcript.get("show_slug"))
    _require_non_empty_string("transcript.duration_hint", transcript.get("duration_hint"))
    _require_non_empty_string("transcript.generation_mode", transcript.get("generation_mode"))

    turns = transcript.get("turns")
    if not isinstance(turns, list) or not turns:
        raise ValueError("transcript must include a non-empty turns list")

    hosts = _require_mapping("hosts", transcript.get("hosts"))
    if set(hosts.keys()) != CANONICAL_SPEAKERS:
        raise ValueError(f"hosts must contain exactly {sorted(CANONICAL_SPEAKERS)}")
    for speaker in CANONICAL_SPEAKERS:
        if speaker not in hosts:
            raise ValueError(f"hosts must include {speaker}")
        host = _require_mapping(f"hosts.{speaker}", hosts[speaker])
        if "default_emotion" in host:
            _validate_emotion(host["default_emotion"], field_name=f"hosts.{speaker}.default_emotion")

    seen_speakers: set[str] = set()
    for index, turn in enumerate(turns):
        turn_obj = _require_mapping(f"turns[{index}]", turn)
        speaker = turn_obj.get("speaker")
        if speaker not in CANONICAL_SPEAKERS:
            raise ValueError(f"turns[{index}].speaker must be one of {sorted(CANONICAL_SPEAKERS)}")
        seen_speakers.add(speaker)
        text = turn_obj.get("text")
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f"turns[{index}].text must be a non-empty string")
        emotion = turn_obj.get("emotion")
        _validate_emotion(emotion, field_name=f"turns[{index}].emotion")
        if "tags" not in turn_obj:
            raise ValueError(f"turns[{index}].tags is required")
        tags = turn_obj.get("tags")
        if not isinstance(tags, list):
            raise ValueError(f"turns[{index}].tags must be a list")
        for tag in tags:
            if tag not in ALLOWED_CHATTERBOX_TAGS:
                raise ValueError(f"turns[{index}].tags contains unsupported tag: {tag}")

        raw_bracket_tokens = extract_bracket_tokens(text)
        inline_tags = extract_inline_tags(text)
        if len(raw_bracket_tokens) != len(inline_tags):
            raise ValueError(f"turns[{index}].text contains malformed inline tag syntax")
        for tag in inline_tags:
            if tag not in ALLOWED_CHATTERBOX_TAGS:
                raise ValueError(f"turns[{index}].text contains unsupported tag: {tag}")
        if tags != inline_tags:
            raise ValueError(f"turns[{index}].tags must match inline tags in text")

    if seen_speakers != CANONICAL_SPEAKERS:
        raise ValueError(f"turns must include both canonical speakers: {sorted(CANONICAL_SPEAKERS)}")

    return transcript


def load_transcript_json(path: str | Path) -> dict[str, Any]:
    transcript_path = Path(path)
    data = json.loads(transcript_path.read_text(encoding="utf-8"))
    return validate_transcript(data)


def save_transcript_json(path: str | Path, data: Any) -> None:
    transcript = validate_transcript(data)
    transcript_path = Path(path)
    transcript_path.parent.mkdir(parents=True, exist_ok=True)
    transcript_path.write_text(
        json.dumps(transcript, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
