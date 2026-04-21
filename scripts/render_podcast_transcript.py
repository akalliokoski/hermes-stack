#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from podcast_transcript_schema import load_transcript_json

DEFAULT_SPEAKER_MAP = {
    "HOST_A": "Person1",
    "HOST_B": "Person2",
}


def normalize_text_whitespace(text: str) -> str:
    return " ".join(text.split())


def speaker_name_for_turn(turn: dict[str, Any], hosts: dict[str, Any]) -> str:
    speaker = turn.get("speaker")
    if speaker not in DEFAULT_SPEAKER_MAP:
        raise ValueError(f"Unsupported speaker: {speaker}")
    host = hosts.get(speaker, {}) if isinstance(hosts, dict) else {}
    if isinstance(host, dict):
        mapped = host.get("podcastfy_speaker")
        if isinstance(mapped, str) and mapped.strip():
            return mapped.strip()
    return DEFAULT_SPEAKER_MAP[speaker]


def render_turn(turn: dict[str, Any], hosts: dict[str, Any]) -> str:
    text = turn.get("text")
    if not isinstance(text, str):
        raise ValueError("turn text must be a string")
    normalized_text = normalize_text_whitespace(text)
    if not normalized_text:
        return ""
    speaker_name = speaker_name_for_turn(turn, hosts)
    return f"<{speaker_name}>{normalized_text}</{speaker_name}>"


def render_for_podcastfy(data: dict[str, Any]) -> str:
    if not isinstance(data, dict):
        raise ValueError("transcript must be an object")
    hosts = data.get("hosts", {})
    turns = data.get("turns", [])
    if not isinstance(turns, list):
        raise ValueError("transcript turns must be a list")

    rendered_turns: list[str] = []
    for turn in turns:
        if not isinstance(turn, dict):
            raise ValueError("turn must be an object")
        rendered = render_turn(turn, hosts)
        if rendered:
            rendered_turns.append(rendered)
    return "\n".join(rendered_turns)


def build_render_metadata(data: dict[str, Any], rendered_text: str) -> dict[str, Any]:
    speakers: list[str] = []
    for line in rendered_text.splitlines():
        if line.startswith("<") and ">" in line:
            speaker = line[1 : line.index(">")]
            if speaker not in speakers:
                speakers.append(speaker)
    return {
        "turn_count": len(rendered_text.splitlines()) if rendered_text else 0,
        "speakers": speakers,
        "source_title": data.get("title"),
        "episode_slug": data.get("episode_slug"),
    }


def write_rendered_outputs(
    data: dict[str, Any],
    *,
    output_path: str | Path,
    metadata_path: str | Path | None = None,
) -> tuple[Path, Path | None]:
    rendered_text = render_for_podcastfy(data)
    destination = Path(output_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(rendered_text + "\n", encoding="utf-8")

    metadata_destination: Path | None = None
    if metadata_path is not None:
        metadata_destination = Path(metadata_path)
        metadata_destination.parent.mkdir(parents=True, exist_ok=True)
        metadata_destination.write_text(
            json.dumps(build_render_metadata(data, rendered_text), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return destination, metadata_destination


def main() -> int:
    parser = argparse.ArgumentParser(description="Render canonical podcast transcript JSON into Podcastfy text")
    parser.add_argument("--input", required=True, help="Path to transcript.json")
    parser.add_argument("--output", help="Path to write rendered transcript text")
    parser.add_argument("--metadata-output", help="Optional path to sidecar render metadata JSON")
    args = parser.parse_args()

    transcript = load_transcript_json(args.input)
    rendered = render_for_podcastfy(transcript)

    if args.output:
        write_rendered_outputs(
            transcript,
            output_path=args.output,
            metadata_path=args.metadata_output,
        )
    else:
        print(rendered)
        if args.metadata_output:
            metadata_path = Path(args.metadata_output)
            metadata_path.parent.mkdir(parents=True, exist_ok=True)
            metadata_path.write_text(
                json.dumps(build_render_metadata(transcript, rendered), indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
