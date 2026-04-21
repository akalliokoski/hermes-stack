#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

JELLYFIN_BASE_URL = os.environ.get("JELLYFIN_BASE_URL", "http://127.0.0.1:8096").rstrip("/")
JELLYFIN_DB_PATH = Path(os.environ.get("JELLYFIN_DB_PATH", "/data/jellyfin/config/data/jellyfin.db"))
JELLYFIN_CONFIG_ROOT = Path(os.environ.get("JELLYFIN_CONFIG_ROOT", "/data/jellyfin/config/root/default"))
JELLYFIN_HOST_PROFILE_VIDEOS_ROOT = Path(os.environ.get("VIDEO_LIBRARY_ROOT", "/data/jellyfin/videos/profiles"))
JELLYFIN_CONTAINER_PROFILE_VIDEOS_ROOT = os.environ.get("JELLYFIN_PROFILE_VIDEOS_PATH_ROOT", "/media/videos/profiles")
JELLYFIN_BOOTSTRAP_WAIT_SECONDS = float(os.environ.get("JELLYFIN_BOOTSTRAP_WAIT_SECONDS", "30"))


def slugify(value: str) -> str:
    return "-".join(part for part in "".join(ch.lower() if ch.isalnum() else "-" for ch in value).split("-") if part) or "default"


def library_name_for_profile(profile_slug: str) -> str:
    if profile_slug == "default":
        return "Default Videos"
    return f"{profile_slug.replace('-', ' ').title()} Videos"


def discover_profiles() -> list[str]:
    profiles = {"default"}
    root = Path("/home/hermes/.hermes/profiles")
    if root.exists():
        for child in root.iterdir():
            if child.is_dir():
                profiles.add(slugify(child.name))
    return sorted(profiles)


def auth_token() -> str:
    explicit = os.environ.get("JELLYFIN_TOKEN", "").strip()
    if explicit:
        return explicit
    if not JELLYFIN_DB_PATH.exists():
        raise RuntimeError(f"Jellyfin DB not found: {JELLYFIN_DB_PATH}")
    with sqlite3.connect(JELLYFIN_DB_PATH) as conn:
        row = conn.execute(
            """
            SELECT AccessToken
            FROM Devices
            WHERE AccessToken IS NOT NULL AND AccessToken != ''
            ORDER BY DateLastActivity DESC, DateModified DESC, Id DESC
            LIMIT 1
            """
        ).fetchone()
    if not row or not isinstance(row[0], str) or not row[0].strip():
        raise RuntimeError("No Jellyfin device token found; set JELLYFIN_TOKEN")
    return row[0].strip()


def request(path: str, *, method: str = "GET", token: str, data: bytes | None = None, headers: dict[str, str] | None = None) -> Any:
    req_headers = {"X-Emby-Token": token}
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(f"{JELLYFIN_BASE_URL}{path}", method=method, data=data, headers=req_headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = resp.read().decode("utf-8", errors="replace")
    if not payload:
        return None
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return payload


def get_virtual_folders(token: str) -> list[dict[str, Any]]:
    payload = request("/Library/VirtualFolders", token=token)
    return payload if isinstance(payload, list) else []


def ensure_virtual_folder(*, token: str, name: str, container_path: str) -> bool:
    existing = get_virtual_folders(token)
    if any(item.get("Name") == name for item in existing):
        return False
    params = urllib.parse.urlencode(
        [
            ("name", name),
            ("collectionType", "homevideos"),
            ("paths", container_path),
            ("refreshLibrary", "true"),
        ]
    )
    request(f"/Library/VirtualFolders?{params}", method="POST", token=token, data=b"")
    return True


def set_realtime_monitor(name: str, enabled: bool = True) -> bool:
    options_path = JELLYFIN_CONFIG_ROOT / name / "options.xml"
    if not options_path.exists():
        return False
    tree = ET.parse(options_path)
    root = tree.getroot()
    node = root.find("EnableRealtimeMonitor")
    if node is None:
        node = ET.SubElement(root, "EnableRealtimeMonitor")
    current = (node.text or "").strip().lower()
    target = "true" if enabled else "false"
    if current == target:
        return False
    node.text = target
    tree.write(options_path, encoding="utf-8", xml_declaration=True)
    return True


def refresh_library(token: str, item_id: str) -> None:
    request(f"/Items/{item_id}/Refresh?Recursive=true", method="POST", token=token, data=b"")


def ensure_profile_video_roots(profiles: list[str]) -> list[str]:
    created: list[str] = []
    for profile in profiles:
        path = JELLYFIN_HOST_PROFILE_VIDEOS_ROOT / profile
        path.mkdir(parents=True, exist_ok=True)
        created.append(str(path))
    return created


def wait_for_server(timeout_seconds: float = JELLYFIN_BOOTSTRAP_WAIT_SECONDS) -> None:
    deadline = time.monotonic() + max(timeout_seconds, 0)
    while True:
        try:
            request("/System/Info/Public", token="")
            return
        except Exception as exc:  # pragma: no cover - runtime-only network behavior
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Jellyfin not ready at {JELLYFIN_BASE_URL}: {exc}") from exc
            time.sleep(1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ensure clean, per-profile Jellyfin video libraries exist and enable realtime monitoring")
    parser.add_argument("--refresh", action="store_true", help="Refresh ensured libraries after creation/update")
    args = parser.parse_args()

    profiles = discover_profiles()
    ensure_profile_video_roots(profiles)

    try:
        wait_for_server()
        token = auth_token()

        target_library_names = {library_name_for_profile(profile) for profile in profiles}
        legacy_library_names = {"AI Generated Videos"}
        created: list[str] = []
        realtime_changed: list[str] = []

        for profile in profiles:
            name = library_name_for_profile(profile)
            container_path = f"{JELLYFIN_CONTAINER_PROFILE_VIDEOS_ROOT}/{profile}"
            if ensure_virtual_folder(token=token, name=name, container_path=container_path):
                created.append(name)
            if set_realtime_monitor(name, enabled=True):
                realtime_changed.append(name)

        for legacy_name in legacy_library_names:
            if set_realtime_monitor(legacy_name, enabled=True):
                realtime_changed.append(legacy_name)

        refreshed: list[str] = []
        if args.refresh:
            for item in get_virtual_folders(token):
                name = item.get("Name", "")
                if name in target_library_names | legacy_library_names:
                    item_id = item.get("ItemId", "")
                    if item_id:
                        refresh_library(token, item_id)
                        refreshed.append(name)

        print(json.dumps({
            "profiles": profiles,
            "created_libraries": created,
            "realtime_monitor_updated": realtime_changed,
            "refreshed_libraries": refreshed,
            "library_root": str(JELLYFIN_HOST_PROFILE_VIDEOS_ROOT),
        }, indent=2))
    except Exception as exc:
        print(f"[bootstrap-jellyfin] warning: skipping library bootstrap: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
