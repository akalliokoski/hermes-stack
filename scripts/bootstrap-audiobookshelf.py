#!/usr/bin/env python3
"""Initialize Audiobookshelf and ensure the podcast library exists.

This script is safe to run on every deploy.
- If Audiobookshelf is not initialized and admin credentials are present, it creates the root user.
- It logs in (or uses AUDIOBOOKSHELF_TOKEN if provided).
- It ensures the configured podcast library exists.
- It triggers a force scan for that library.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any

BASE_URL = os.environ.get("AUDIOBOOKSHELF_BASE_URL", "http://127.0.0.1:13378").rstrip("/")
USERNAME = os.environ.get("AUDIOBOOKSHELF_ADMIN_USERNAME", "")
PASSWORD = os.environ.get("AUDIOBOOKSHELF_ADMIN_PASSWORD", "")
TOKEN = os.environ.get("AUDIOBOOKSHELF_TOKEN", "")
LIBRARY_NAME = os.environ.get("AUDIOBOOKSHELF_LIBRARY_NAME", "AI Generated Podcasts")
PODCASTS_PATH = os.environ.get("AUDIOBOOKSHELF_PODCASTS_PATH", "/podcasts")


def log(message: str) -> None:
    print(f"[bootstrap-audiobookshelf] {message}")


def request(path: str, method: str = "GET", data: dict[str, Any] | None = None, token: str | None = None) -> tuple[int, str]:
    headers: dict[str, str] = {}
    body = None
    auth_token = token or TOKEN
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{BASE_URL}{path}", data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} for {method} {path}: {detail}") from exc


def wait_for_server() -> dict[str, Any]:
    last_error: Exception | None = None
    for _ in range(60):
        try:
            _, body = request("/status")
            return json.loads(body)
        except Exception as exc:  # pragma: no cover - best-effort bootstrap
            last_error = exc
            time.sleep(2)
    raise RuntimeError(f"Audiobookshelf did not become ready at {BASE_URL}: {last_error}")


def ensure_initialized(status: dict[str, Any]) -> None:
    if status.get("isInit"):
        log("server already initialized")
        return
    if not USERNAME or not PASSWORD:
        log("server is uninitialized but admin credentials are not configured; leaving first-run setup for the web UI")
        sys.exit(0)
    log(f"initializing server with root user '{USERNAME}'")
    request("/init", method="POST", data={"newRoot": {"username": USERNAME, "password": PASSWORD}})


def get_token() -> str:
    if TOKEN:
        log("using API token from environment")
        return TOKEN
    if not USERNAME or not PASSWORD:
        log("no API token or admin credentials configured; skipping API bootstrap")
        sys.exit(0)
    _, body = request("/login", method="POST", data={"username": USERNAME, "password": PASSWORD})
    payload = json.loads(body)
    token = payload["user"]["token"]
    log("logged in successfully")
    return token


def ensure_library(token: str) -> str:
    _, body = request("/api/libraries", token=token)
    libraries = json.loads(body).get("libraries", [])
    for library in libraries:
        if library.get("name") == LIBRARY_NAME:
            log(f"library already exists: {LIBRARY_NAME}")
            return library["id"]

    log(f"creating library: {LIBRARY_NAME} ({PODCASTS_PATH})")
    _, body = request(
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
    return json.loads(body)["id"]


def scan_library(token: str, library_id: str) -> None:
    request(f"/api/libraries/{library_id}/scan?force=1", method="POST", token=token)
    log(f"triggered library scan for {library_id}")


def main() -> int:
    status = wait_for_server()
    ensure_initialized(status)
    token = get_token()
    library_id = ensure_library(token)
    scan_library(token, library_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
