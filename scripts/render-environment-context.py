#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import platform
import socket
from pathlib import Path
from typing import Any

import yaml


def expand(value: Any) -> Any:
    if isinstance(value, str):
        return os.path.expandvars(os.path.expanduser(value))
    if isinstance(value, list):
        return [expand(item) for item in value]
    if isinstance(value, dict):
        return {key: expand(val) for key, val in value.items()}
    return value


def load_yaml(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text()) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"Expected mapping in {path}")
    return expand(data)


def bool_text(value: bool) -> str:
    return 'yes' if value else 'no'


def select_service_url(service: dict[str, Any], service_mode: str) -> str | None:
    if service_mode == 'local':
        for key in ('local_api_url', 'local_gui_url', 'optional_local_api_url', 'optional_local_gui_url', 'api_url', 'ui_url', 'gui_url', 'landing_url'):
            value = service.get(key)
            if value:
                return str(value)
        return None

    if service_mode in ('remote', 'auto'):
        if service_mode == 'auto' and str(service.get('mode', '')).startswith('local'):
            for key in ('local_api_url', 'local_gui_url', 'api_url', 'ui_url', 'gui_url', 'landing_url', 'optional_local_api_url', 'optional_local_gui_url'):
                value = service.get(key)
                if value:
                    return str(value)
        for key in ('remote_api_url', 'remote_ui_url', 'remote_gui_url', 'api_url', 'ui_url', 'gui_url', 'landing_url', 'optional_remote_api_url', 'optional_remote_ui_url', 'optional_remote_gui_url'):
            value = service.get(key)
            if value:
                return str(value)
        if service_mode == 'auto':
            for key in ('optional_local_api_url', 'optional_local_gui_url', 'local_api_url', 'local_gui_url'):
                value = service.get(key)
                if value:
                    return str(value)
        return None

    raise SystemExit(f'Unsupported service mode: {service_mode}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-root', default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument('--env-id', required=True)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--profile-home', required=True)
    parser.add_argument('--config-path', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--service-mode', choices=['auto', 'local', 'remote'], default=os.environ.get('HERMES_SERVICE_MODE', 'auto'))
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    env_path = repo_root / 'config' / 'env' / f'{args.env_id}.yaml'
    manifest = load_yaml(env_path)
    env = manifest.get('env') or {}
    capabilities = env.get('capabilities') or {}
    services = env.get('services') or {}

    profile_home = Path(os.path.expanduser(args.profile_home))
    config_path = Path(os.path.expanduser(args.config_path))

    lines: list[str] = []
    lines.append('# Runtime Environment')
    lines.append('')
    lines.append('This section is generated automatically. Treat it as the live environment contract for this machine.')
    lines.append('')
    lines.append(f'- Environment ID: `{env.get("id", args.env_id)}`')
    lines.append(f'- Role: `{env.get("role", "unknown")}`')
    lines.append(f'- Detected hostname: `{socket.gethostname()}`')
    lines.append(f'- Declared hostname: `{env.get("hostname", "unknown")}`')
    lines.append(f'- OS: `{platform.system()} {platform.release()}`')
    lines.append(f'- Current user: `{os.environ.get("USER") or os.environ.get("USERNAME") or "unknown"}`')
    lines.append(f'- Profile: `{args.profile}`')
    lines.append(f'- Profile home: `{profile_home}` (exists: {bool_text(profile_home.exists())})')
    lines.append(f'- Config path: `{config_path}` (exists: {bool_text(config_path.exists())})')
    lines.append(f'- Declared work root: `{env.get("work_root", "unknown")}`')
    lines.append(f'- Declared wiki path: `{env.get("wiki_path", "unknown")}`')
    lines.append(f'- Service mode preference: `{args.service_mode}`')
    lines.append('')
    lines.append('## Capabilities')
    lines.append('')
    for key in sorted(capabilities):
        lines.append(f'- `{key}`: {bool_text(bool(capabilities[key]))}')
    if not capabilities:
        lines.append('- No declared capabilities found.')
    lines.append('')
    lines.append('## Service Endpoints')
    lines.append('')
    if services:
        for name in sorted(services):
            service = services[name] or {}
            mode = service.get('mode', 'unknown')
            preferred = select_service_url(service, args.service_mode)
            lines.append(f'- `{name}` ({mode})')
            if preferred:
                lines.append(f'  - preferred_url[{args.service_mode}]: `{preferred}`')
            for field, value in service.items():
                if field == 'mode':
                    continue
                lines.append(f'  - {field}: `{value}`')
    else:
        lines.append('- No declared services found.')
    lines.append('')
    lines.append('## Operating Rules')
    lines.append('')
    lines.append('- Prefer declared capabilities over hostname guesses.')
    lines.append('- Only claim local control of Docker, systemd, or Tailscale if the capability list above says it is available.')
    lines.append('- If a service is declared as remote, use the listed remote endpoint instead of assuming a localhost service exists.')
    lines.append('- When performing machine-specific actions, explain whether the action is local to this machine or routed to the VPS over Tailscale.')

    Path(args.output).write_text('\n'.join(lines).rstrip() + '\n')


if __name__ == '__main__':
    main()
