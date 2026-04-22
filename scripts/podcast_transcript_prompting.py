from __future__ import annotations

import json
import textwrap
from pathlib import Path
from typing import Any

HOST_PROFILES = textwrap.dedent(
    """
    HOST_A — The Connector
    - opens threads and adds context
    - slightly longer sentences with spoken cadence, contractions, and occasional contrastive emphasis
    - bridges topics and frames stakes
    - occasional self-correction, aside, or soft reaction when a point lands
    - should sound warm, engaged, and lightly animated rather than lecturer-flat
    - default emotion around 0.8

    HOST_B — The Interrogator
    - shorter, punchier responses with sharper sentence-length variation
    - pressure-tests claims and calls out weak framing
    - uses interruptions, reframings, quick reactions, and incredulous pivots
    - drives pivots and tension
    - should sound more skeptical, amused, or urgent when the material supports it
    - default emotion around 0.75
    """
).strip()

EPISODE_STRUCTURE_RULES = textwrap.dedent(
    """
    Default episode arc:
    - cold open: 1-2 turns
    - context frame: 2-3 turns
    - topic 1: 6-8 turns
    - pivot: 1-2 turns
    - topic 2: 6-8 turns
    - synthesis: 3-4 turns
    - close: 1-2 turns

    Avoid sterile intro/outro boilerplate unless explicitly requested.
    Write for spoken delivery, not essay prose.
    Use contractions, sentence-length variation, quick reactions, and occasional friction so the exchange sounds performed rather than narrated.
    Let emotion move visibly across the episode: curiosity -> tension/surprise -> synthesis/release.
    At least a few turns should feel playful, skeptical, surprised, or emphatic when the sources support it.
    Allowed inline tags only: [laugh], [chuckle], [sigh], [gasp], [cough].
    Tags must follow a completed clause or sentence and should stay rare.
    Store numeric emotion values per turn.
    """
).strip()

CANONICAL_JSON_EXAMPLE = {
    "version": 1,
    "title": "Example Episode",
    "episode_slug": "example-episode",
    "show_slug": "example-show",
    "duration_hint": "medium",
    "generation_mode": "podcastfy_compat",
    "hosts": {
        "HOST_A": {"role": "connector", "default_emotion": 0.8, "podcastfy_speaker": "Person1"},
        "HOST_B": {"role": "interrogator", "default_emotion": 0.75, "podcastfy_speaker": "Person2"},
    },
    "turns": [
        {
            "turn_id": "t01",
            "speaker": "HOST_A",
            "text": "Memory used to feel optional. [chuckle]",
            "emotion": 0.82,
            "tags": ["chuckle"],
            "notes": ["cold_open", "topic_intro"],
        }
    ],
}


def build_source_packet(*, files: list[Path], urls: list[str], topic: str | None, notes: str | None) -> dict[str, Any]:
    return {
        "files": [str(path) for path in files],
        "urls": list(urls),
        "topic": topic or "none",
        "notes": notes or "none",
    }


def format_source_packet(source_packet: dict[str, Any]) -> str:
    file_lines = "\n".join(f"- {path}" for path in source_packet.get("files", [])) or "- none"
    url_lines = "\n".join(f"- {url}" for url in source_packet.get("urls", [])) or "- none"
    topic_line = source_packet.get("topic", "none")
    notes_line = source_packet.get("notes", "none")
    return textwrap.dedent(
        f"""
        Local files:
        {file_lines}

        URLs:
        {url_lines}

        Topic hint:
        {topic_line}

        Extra instructions:
        {notes_line}
        """
    ).strip()


def build_draft_prompt(*, title: str, source_packet: dict[str, Any]) -> str:
    return textwrap.dedent(
        f"""
        Create a source-grounded two-host podcast transcript for the episode titled: {title}

        Use Hermes tools to read the listed local files and fetch any URLs if needed.

        {format_source_packet(source_packet)}

        Host profiles:
        {HOST_PROFILES}

        Craft rules:
        {EPISODE_STRUCTURE_RULES}

        Return ONLY canonical JSON.
        No markdown fences. No commentary.
        Use exactly two speakers: HOST_A and HOST_B.
        Keep claims grounded in the provided sources.
        Target roughly 6 to 12 minutes of spoken audio unless the source volume clearly justifies more.
        Include per-turn emotion values and tags that match inline text tags exactly.
        Prioritize vocal texture: contractions, interruptions, rebuttals, callbacks, short reactions, and occasional surprise when justified.
        Avoid long runs of evenly explanatory turns that would sound flat in TTS.

        Canonical JSON example:
        {json.dumps(CANONICAL_JSON_EXAMPLE, indent=2, sort_keys=True)}
        """
    ).strip()


def build_revision_prompt(*, title: str, source_packet: dict[str, Any], draft_transcript: dict[str, Any]) -> str:
    return textwrap.dedent(
        f"""
        Revise the canonical podcast transcript JSON for the episode titled: {title}.

        Use the same sources and keep every factual claim grounded.

        {format_source_packet(source_packet)}

        Host profiles:
        {HOST_PROFILES}

        Rewrite checks:
        - make speakers more distinct
        - remove “as you know” exposition
        - make every exchange do at least two jobs where possible
        - smooth emotion arc
        - create stronger emotional contrast instead of keeping every turn evenly composed
        - add more spoken rhythm: contractions, pivots, interruptions, callbacks, and short reactions where natural
        - reduce tag overuse while still letting a few turns feel performative
        - keep sentences punchy enough for TTS and avoid textbook-flat explanation blocks
        - keep claims grounded in source material

        Return ONLY revised canonical JSON.
        No markdown fences. No commentary.
        Preserve the same schema and speaker labels.

        Draft transcript JSON:
        {json.dumps(draft_transcript, indent=2, sort_keys=True)}
        """
    ).strip()
