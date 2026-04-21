from __future__ import annotations

import re
from typing import Any

from podcast_transcript_schema import ALLOWED_CHATTERBOX_TAGS, validate_transcript

ALL_BRACKET_TAG_PATTERN = re.compile(r"\[([^\]]+)\]")
STACKED_TAG_PATTERN = re.compile(r"\[[^\]]+\]\s*\[[^\]]+\]")
CLAUSE_ENDING = {".", "!", "?", ";", ":"}
SHORT_EPISODE_TAG_LIMIT = 3
GASP_WARNING_THRESHOLD = 2
COUGH_WARNING_THRESHOLD = 1
EMOTION_PEAK_THRESHOLD = 0.85
EMOTION_FLAT_SPREAD_THRESHOLD = 0.05
SPEAKER_IMBALANCE_THRESHOLD = 0.75
EARLY_PEAK_FRACTION = 0.33


def validate_tag_placement(text: str) -> list[str]:
    if not isinstance(text, str):
        raise ValueError("text must be a string")

    messages: list[str] = []
    matches = list(ALL_BRACKET_TAG_PATTERN.finditer(text))
    for match in matches:
        tag = match.group(1).strip()
        if tag not in ALLOWED_CHATTERBOX_TAGS:
            messages.append(f"unsupported tag: {tag}")

        prefix = text[: match.start()].rstrip()
        if prefix and prefix[-1] not in CLAUSE_ENDING:
            messages.append(f"tag [{tag}] must follow completed clause or sentence")

    if STACKED_TAG_PATTERN.search(text):
        messages.append("multiple inline tags in a row are not allowed")

    return messages


def emotion_arc_summary(turns: list[dict[str, Any]]) -> dict[str, Any]:
    emotions = [float(turn["emotion"]) for turn in turns if isinstance(turn, dict) and "emotion" in turn]
    if not emotions:
        return {
            "turn_count": 0,
            "min_emotion": None,
            "max_emotion": None,
            "spread": None,
            "peak_value": None,
            "peak_turn_index": None,
            "flat": False,
            "peak_too_early": False,
            "missing_peak": True,
        }

    min_emotion = min(emotions)
    max_emotion = max(emotions)
    spread = max_emotion - min_emotion
    missing_peak = max_emotion < EMOTION_PEAK_THRESHOLD
    peak_turn_index = None if missing_peak else emotions.index(max_emotion)
    early_cutoff = max(1, int(len(emotions) * EARLY_PEAK_FRACTION))
    peak_too_early = peak_turn_index is not None and peak_turn_index < early_cutoff

    return {
        "turn_count": len(emotions),
        "min_emotion": min_emotion,
        "max_emotion": max_emotion,
        "spread": spread,
        "peak_value": None if missing_peak else max_emotion,
        "peak_turn_index": peak_turn_index,
        "flat": spread <= EMOTION_FLAT_SPREAD_THRESHOLD,
        "peak_too_early": peak_too_early,
        "missing_peak": missing_peak,
    }


def speaker_balance_summary(turns: list[dict[str, Any]]) -> dict[str, Any]:
    counts: dict[str, int] = {}
    for turn in turns:
        speaker = turn.get("speaker") if isinstance(turn, dict) else None
        if isinstance(speaker, str):
            counts[speaker] = counts.get(speaker, 0) + 1

    total_turns = sum(counts.values())
    if not total_turns:
        return {
            "counts": {},
            "total_turns": 0,
            "dominant_speaker": None,
            "dominant_share": 0.0,
            "imbalanced": False,
        }

    dominant_speaker = max(counts, key=counts.get)
    dominant_share = counts[dominant_speaker] / total_turns
    return {
        "counts": counts,
        "total_turns": total_turns,
        "dominant_speaker": dominant_speaker,
        "dominant_share": dominant_share,
        "imbalanced": dominant_share > SPEAKER_IMBALANCE_THRESHOLD,
    }


def audit_transcript(data: Any) -> dict[str, Any]:
    issues: list[dict[str, Any]] = []

    try:
        transcript = validate_transcript(data)
    except ValueError as exc:
        return {
            "ok": False,
            "issues": [
                {
                    "severity": "error",
                    "code": "structural_invalidity",
                    "message": str(exc),
                }
            ],
            "summaries": {},
        }

    turns = transcript["turns"]
    tag_count = 0
    gasp_count = 0
    cough_count = 0
    for index, turn in enumerate(turns):
        text = turn.get("text", "")
        tags = turn.get("tags", [])
        tag_count += len(tags)
        gasp_count += tags.count("gasp")
        cough_count += tags.count("cough")

        for message in validate_tag_placement(text):
            code = "tag_placement"
            severity = "warning"
            if message.startswith("unsupported tag:"):
                code = "unknown_inline_tag"
                severity = "error"
            elif "multiple inline tags" in message:
                code = "stacked_inline_tags"
            issues.append(
                {
                    "severity": severity,
                    "code": code,
                    "message": f"turn {index + 1}: {message}",
                }
            )

    if transcript.get("duration_hint") == "short" and tag_count > SHORT_EPISODE_TAG_LIMIT:
        issues.append(
            {
                "severity": "warning",
                "code": "tag_density_short_episode",
                "message": f"short episode has {tag_count} total inline tags; consider using fewer paralinguistic tags",
            }
        )

    if gasp_count >= GASP_WARNING_THRESHOLD:
        issues.append(
            {
                "severity": "warning",
                "code": "gasp_overuse",
                "message": f"[gasp] appears {gasp_count} times and should stay extremely rare",
            }
        )

    if cough_count >= COUGH_WARNING_THRESHOLD:
        issues.append(
            {
                "severity": "warning",
                "code": "cough_suspicious",
                "message": f"[cough] appears {cough_count} times and usually sounds suspicious or awkward in podcast dialogue",
            }
        )

    balance = speaker_balance_summary(turns)
    if balance["imbalanced"]:
        issues.append(
            {
                "severity": "warning",
                "code": "speaker_imbalance",
                "message": (
                    f"{balance['dominant_speaker']} carries {balance['dominant_share']:.0%} of turns; "
                    "speaker balance may be too one-sided"
                ),
            }
        )

    emotion = emotion_arc_summary(turns)
    if emotion["flat"]:
        issues.append(
            {
                "severity": "warning",
                "code": "flat_emotion_arc",
                "message": "emotion arc looks flat across turns",
            }
        )
    if emotion["peak_too_early"]:
        issues.append(
            {
                "severity": "warning",
                "code": "early_emotion_peak",
                "message": "peak emotion lands too early in the episode",
            }
        )
    if emotion["missing_peak"]:
        issues.append(
            {
                "severity": "warning",
                "code": "missing_emotion_peak",
                "message": "episode never reaches a clear emotional peak",
            }
        )

    if not issues:
        issues.append(
            {
                "severity": "info",
                "code": "audit_clean",
                "message": "no transcript audit issues detected",
            }
        )

    return {
        "ok": not any(issue["severity"] == "error" for issue in issues),
        "issues": issues,
        "summaries": {
            "speaker_balance": balance,
            "emotion_arc": emotion,
            "tag_count": tag_count,
            "gasp_count": gasp_count,
        },
    }
