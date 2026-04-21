#!/usr/bin/env python3
"""Reusable Audiobookshelf REST helpers for Hermes stack podcast tooling."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from podcast_pipeline_common import (
    DEFAULT_AUDIOBOOKSHELF_BASE_URL,
    current_profile_slug,
    podcast_library_name,
    slugify,
)

BASE_URL = os.environ.get("AUDIOBOOKSHELF_BASE_URL", DEFAULT_AUDIOBOOKSHELF_BASE_URL).rstrip("/")
TOKEN = os.environ.get("AUDIOBOOKSHELF_TOKEN", "")
USERNAME = os.environ.get("AUDIOBOOKSHELF_ADMIN_USERNAME", "")
PASSWORD = os.environ.get("AUDIOBOOKSHELF_ADMIN_PASSWORD", "")
LIBRARY_NAME = os.environ.get("AUDIOBOOKSHELF_LIBRARY_NAME", "AI Generated Podcasts")
PODCASTS_PATH = os.environ.get("AUDIOBOOKSHELF_PODCASTS_PATH", "/podcasts")
PROFILE_PODCASTS_PATH_ROOT = os.environ.get("AUDIOBOOKSHELF_PROFILE_PODCASTS_PATH_ROOT", "/podcasts/profiles")
LOCAL_DB_PATH = Path(os.environ.get("AUDIOBOOKSHELF_DB_PATH", "/data/audiobookshelf/config/absdatabase.sqlite"))


def request(path: str, method: str = "GET", data: dict[str, Any] | None = None, token: str | None = None) -> dict[str, Any] | list[Any] | str:
    auth_token = token or TOKEN
    headers: dict[str, str] = {}
    body = None
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(f"{BASE_URL}{path}", data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} for {method} {path}: {detail}") from exc

    if not payload:
        return {"ok": True}
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return payload


def wait_for_server(attempts: int = 60, delay_seconds: int = 2) -> dict[str, Any]:
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            payload = request("/status")
            if isinstance(payload, dict):
                return payload
            raise RuntimeError(f"Unexpected /status payload: {payload!r}")
        except Exception as exc:  # pragma: no cover - best effort operational helper
            last_error = exc
            time.sleep(delay_seconds)
    raise RuntimeError(f"Audiobookshelf did not become ready at {BASE_URL}: {last_error}")


def ensure_initialized(status: dict[str, Any]) -> bool:
    if status.get("isInit"):
        return False
    if not USERNAME or not PASSWORD:
        raise RuntimeError(
            "Audiobookshelf is uninitialized. Set AUDIOBOOKSHELF_ADMIN_USERNAME and AUDIOBOOKSHELF_ADMIN_PASSWORD to bootstrap it."
        )
    request("/init", method="POST", data={"newRoot": {"username": USERNAME, "password": PASSWORD}})
    return True


def local_token_from_db() -> str:
    if not LOCAL_DB_PATH.exists():
        return ""
    try:
        with sqlite3.connect(LOCAL_DB_PATH) as conn:
            row = conn.execute(
                """
                SELECT token
                FROM users
                WHERE isActive = 1
                  AND token IS NOT NULL
                  AND token != ''
                ORDER BY CASE WHEN type = 'root' THEN 0 ELSE 1 END, updatedAt DESC
                LIMIT 1
                """
            ).fetchone()
    except sqlite3.Error:
        return ""
    if not row:
        return ""
    token = row[0]
    return token if isinstance(token, str) else ""


def login() -> str:
    if TOKEN:
        return TOKEN
    if USERNAME and PASSWORD:
        payload = request("/login", method="POST", data={"username": USERNAME, "password": PASSWORD})
        if not isinstance(payload, dict):
            raise RuntimeError(f"Unexpected /login payload: {payload!r}")
        return payload["user"]["token"]
    local_token = local_token_from_db()
    if local_token:
        return local_token
    raise RuntimeError(
        "Set AUDIOBOOKSHELF_TOKEN or AUDIOBOOKSHELF_ADMIN_USERNAME/AUDIOBOOKSHELF_ADMIN_PASSWORD, or run on a host that can read the local Audiobookshelf database token cache"
    )


def discover_profiles() -> list[str]:
    profiles = {"default"}
    root = Path("/home/hermes/.hermes/profiles")
    if root.exists():
        for child in root.iterdir():
            if child.is_dir():
                profiles.add(slugify(child.name))
    return sorted(profiles)


def profile_library_path(profile_slug: str) -> str:
    return f"{PROFILE_PODCASTS_PATH_ROOT.rstrip('/')}/{profile_slug}"


def libraries(token: str) -> dict[str, Any]:
    payload = request("/api/libraries", token=token)
    if not isinstance(payload, dict):
        raise RuntimeError(f"Unexpected /api/libraries payload: {payload!r}")
    return payload


def find_library(token: str, *, name: str) -> dict[str, Any] | None:
    current = libraries(token).get("libraries", [])
    for library in current:
        if library.get("name") == name:
            return library
    return None


def ensure_library(token: str, *, name: str = LIBRARY_NAME, podcasts_path: str = PODCASTS_PATH) -> dict[str, Any]:
    existing = find_library(token, name=name)
    if existing:
        return existing
    payload = request(
        "/api/libraries",
        method="POST",
        token=token,
        data={
            "name": name,
            "folders": [{"fullPath": podcasts_path}],
            "mediaType": "podcast",
            "icon": "podcast",
        },
    )
    if not isinstance(payload, dict):
        raise RuntimeError(f"Unexpected library creation payload: {payload!r}")
    return payload


def ensure_profile_library(token: str, profile_slug: str) -> dict[str, Any]:
    normalized = slugify(profile_slug)
    return ensure_library(
        token,
        name=podcast_library_name(normalized),
        podcasts_path=profile_library_path(normalized),
    )


def scan_library(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/scan?force=1", method="POST", token=token)


def recent_episodes(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/recent-episodes", token=token)


def library_items(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/items", token=token)


def library_stats(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/stats", token=token)


def ensure_library_and_scan(*, name: str = LIBRARY_NAME, podcasts_path: str = PODCASTS_PATH) -> tuple[dict[str, Any], dict[str, Any] | str]:
    token = login()
    library = ensure_library(token, name=name, podcasts_path=podcasts_path)
    scan_payload = scan_library(token, library["id"])
    return library, scan_payload


def ensure_profile_library_and_scan(profile_slug: str) -> tuple[dict[str, Any], dict[str, Any] | str]:
    token = login()
    library = ensure_profile_library(token, profile_slug)
    scan_payload = scan_library(token, library["id"])
    return library, scan_payload


def ensure_profile_libraries_and_scan(profiles: list[str] | None = None) -> list[dict[str, Any]]:
    token = login()
    summaries: list[dict[str, Any]] = []
    for profile_slug in profiles or discover_profiles():
        library = ensure_profile_library(token, profile_slug)
        scan_payload = scan_library(token, library["id"])
        summaries.append({
            "profile": slugify(profile_slug),
            "library": library,
            "scan": scan_payload,
        })
    return summaries


def _print(payload: dict[str, Any] | list[Any] | str) -> None:
    if isinstance(payload, (dict, list)):
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audiobookshelf API helpers for Hermes podcast tooling")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("login")
    sub.add_parser("libraries")

    ensure_library_parser = sub.add_parser("ensure-library")
    ensure_library_parser.add_argument("--name", default=LIBRARY_NAME)
    ensure_library_parser.add_argument("--path", dest="podcasts_path", default=PODCASTS_PATH)
    ensure_library_parser.add_argument("--profile")

    bootstrap = sub.add_parser("bootstrap")
    bootstrap.add_argument("--all-profiles", action="store_true")
    bootstrap.add_argument("--profile")

    scan = sub.add_parser("scan")
    scan.add_argument("--library-id")
    scan.add_argument("--profile")

    recent = sub.add_parser("recent")
    recent.add_argument("--library-id")
    recent.add_argument("--profile")

    items = sub.add_parser("items")
    items.add_argument("--library-id")
    items.add_argument("--profile")

    stats = sub.add_parser("stats")
    stats.add_argument("--library-id")
    stats.add_argument("--profile")

    args = parser.parse_args()

    try:
        if args.cmd == "status":
            _print(wait_for_server())
            return 0
        if args.cmd == "login":
            print(login())
            return 0
        if args.cmd == "libraries":
            _print(libraries(login()))
            return 0
        if args.cmd == "ensure-library":
            token = login()
            if args.profile:
                _print(ensure_profile_library(token, args.profile))
            else:
                _print(ensure_library(token, name=args.name, podcasts_path=args.podcasts_path))
            return 0
        if args.cmd == "bootstrap":
            status = wait_for_server()
            ensure_initialized(status)
            if args.all_profiles:
                _print(ensure_profile_libraries_and_scan())
            elif args.profile:
                library, payload = ensure_profile_library_and_scan(args.profile)
                _print({"library": library, "scan": payload})
            else:
                library, payload = ensure_library_and_scan()
                _print({"library": library, "scan": payload})
            return 0
        if args.cmd in {"scan", "recent", "items", "stats"}:
            token = login()
            if args.library_id:
                library_id = args.library_id
            elif args.profile:
                library_id = ensure_profile_library(token, args.profile)["id"]
            else:
                library_id = ensure_profile_library(token, current_profile_slug())["id"]
            if args.cmd == "scan":
                _print(scan_library(token, library_id))
            elif args.cmd == "recent":
                _print(recent_episodes(token, library_id))
            elif args.cmd == "items":
                _print(library_items(token, library_id))
            else:
                _print(library_stats(token, library_id))
            return 0
    except RuntimeError as exc:
        raise SystemExit(str(exc)) from exc

    raise SystemExit(f"Unknown command: {args.cmd}")


if __name__ == "__main__":
    raise SystemExit(main())
