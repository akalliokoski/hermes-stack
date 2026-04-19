#!/usr/bin/env python3
"""Reusable Audiobookshelf REST helpers for Hermes stack podcast tooling."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any

BASE_URL = os.environ.get("AUDIOBOOKSHELF_BASE_URL", "http://127.0.0.1:13378").rstrip("/")
TOKEN = os.environ.get("AUDIOBOOKSHELF_TOKEN", "")
USERNAME = os.environ.get("AUDIOBOOKSHELF_ADMIN_USERNAME", "")
PASSWORD = os.environ.get("AUDIOBOOKSHELF_ADMIN_PASSWORD", "")
LIBRARY_NAME = os.environ.get("AUDIOBOOKSHELF_LIBRARY_NAME", "AI Generated Podcasts")
PODCASTS_PATH = os.environ.get("AUDIOBOOKSHELF_PODCASTS_PATH", "/podcasts")


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


def login() -> str:
    if TOKEN:
        return TOKEN
    if not USERNAME or not PASSWORD:
        raise RuntimeError("Set AUDIOBOOKSHELF_TOKEN or AUDIOBOOKSHELF_ADMIN_USERNAME/AUDIOBOOKSHELF_ADMIN_PASSWORD")
    payload = request("/login", method="POST", data={"username": USERNAME, "password": PASSWORD})
    if not isinstance(payload, dict):
        raise RuntimeError(f"Unexpected /login payload: {payload!r}")
    return payload["user"]["token"]


def libraries(token: str) -> dict[str, Any]:
    payload = request("/api/libraries", token=token)
    if not isinstance(payload, dict):
        raise RuntimeError(f"Unexpected /api/libraries payload: {payload!r}")
    return payload


def ensure_library(token: str) -> dict[str, Any]:
    current = libraries(token).get("libraries", [])
    for library in current:
        if library.get("name") == LIBRARY_NAME:
            return library
    payload = request(
        "/api/libraries",
        method="POST",
        token=token,
        data={
            "name": LIBRARY_NAME,
            "folders": [{"fullPath": PODCASTS_PATH}],
            "mediaType": "podcast",
            "icon": "podcast",
        },
    )
    if not isinstance(payload, dict):
        raise RuntimeError(f"Unexpected library creation payload: {payload!r}")
    return payload


def scan_library(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/scan?force=1", method="POST", token=token)


def recent_episodes(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/recent-episodes", token=token)


def library_items(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/items", token=token)


def library_stats(token: str, library_id: str) -> dict[str, Any] | str:
    return request(f"/api/libraries/{library_id}/stats", token=token)


def ensure_library_and_scan() -> tuple[dict[str, Any], dict[str, Any] | str]:
    token = login()
    library = ensure_library(token)
    scan_payload = scan_library(token, library["id"])
    return library, scan_payload


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
    sub.add_parser("ensure-library")
    sub.add_parser("bootstrap")
    scan = sub.add_parser("scan")
    scan.add_argument("--library-id")
    recent = sub.add_parser("recent")
    recent.add_argument("--library-id")
    items = sub.add_parser("items")
    items.add_argument("--library-id")
    stats = sub.add_parser("stats")
    stats.add_argument("--library-id")
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
            _print(ensure_library(login()))
            return 0
        if args.cmd == "bootstrap":
            status = wait_for_server()
            ensure_initialized(status)
            library, payload = ensure_library_and_scan()
            _print({"library": library, "scan": payload})
            return 0
        if args.cmd == "scan":
            token = login()
            library = ensure_library(token) if not args.library_id else {"id": args.library_id}
            _print(scan_library(token, library["id"]))
            return 0
        if args.cmd == "recent":
            token = login()
            library = ensure_library(token) if not args.library_id else {"id": args.library_id}
            _print(recent_episodes(token, library["id"]))
            return 0
        if args.cmd == "items":
            token = login()
            library = ensure_library(token) if not args.library_id else {"id": args.library_id}
            _print(library_items(token, library["id"]))
            return 0
        if args.cmd == "stats":
            token = login()
            library = ensure_library(token) if not args.library_id else {"id": args.library_id}
            _print(library_stats(token, library["id"]))
            return 0
    except RuntimeError as exc:
        raise SystemExit(str(exc)) from exc

    raise SystemExit(f"Unknown command: {args.cmd}")


if __name__ == "__main__":
    raise SystemExit(main())
