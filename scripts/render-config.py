#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import os
from pathlib import Path
from typing import Any

import yaml


def expand(value: Any, *, target_home: str | None = None) -> Any:
    if isinstance(value, str):
        expanded = os.path.expandvars(value)
        if expanded == '~' and target_home:
            return target_home
        if expanded.startswith('~/') and target_home:
            return str(Path(target_home) / expanded[2:])
        return expanded
    if isinstance(value, list):
        return [expand(item, target_home=target_home) for item in value]
    if isinstance(value, dict):
        return {key: expand(val, target_home=target_home) for key, val in value.items()}
    return value


def deep_merge(base: Any, overlay: Any) -> Any:
    if isinstance(base, dict) and isinstance(overlay, dict):
        merged = {key: copy.deepcopy(val) for key, val in base.items()}
        for key, value in overlay.items():
            if key in merged:
                merged[key] = deep_merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged
    return copy.deepcopy(overlay)


def load_yaml(path: Path, *, target_home: str | None = None) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text()) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"Expected mapping in {path}")
    return expand(data, target_home=target_home)


def get_path(data: dict[str, Any], dotted: str) -> Any:
    current: Any = data
    for part in dotted.split('.'):
        if not isinstance(current, dict) or part not in current:
            raise SystemExit(f"Missing key: {dotted}")
        current = current[part]
    return current


def select_service_url(service: dict[str, Any], service_mode: str) -> str:
    if service_mode == 'local':
        for key in ('local_api_url', 'optional_local_api_url', 'api_url'):
            value = service.get(key)
            if value:
                return str(value)
    elif service_mode in ('remote', 'auto'):
        if service_mode == 'auto' and str(service.get('mode', '')).startswith('local'):
            for key in ('local_api_url', 'api_url', 'optional_local_api_url'):
                value = service.get(key)
                if value:
                    return str(value)
        for key in ('remote_api_url', 'api_url', 'optional_remote_api_url'):
            value = service.get(key)
            if value:
                return str(value)
        if service_mode == 'auto':
            for key in ('optional_local_api_url', 'local_api_url'):
                value = service.get(key)
                if value:
                    return str(value)
    raise SystemExit(f"Could not determine service URL for mode={service_mode!r} service={service}")


def apply_profile_overrides(config: dict[str, Any], manifest: dict[str, Any], profile: str) -> dict[str, Any]:
    work_root = get_path(manifest, 'env.work_root')
    terminal = config.setdefault('terminal', {})
    docker_volumes = terminal.get('docker_volumes')
    desired = f"{work_root}/{profile}:/workspace"
    if docker_volumes is None:
        terminal['docker_volumes'] = [desired]
    elif isinstance(docker_volumes, list):
        updated = []
        replaced = False
        for entry in docker_volumes:
            entry_str = str(entry)
            if entry_str.endswith(':/workspace') and not replaced:
                updated.append(desired)
                replaced = True
            else:
                updated.append(entry_str)
        if not replaced:
            updated.append(desired)
        terminal['docker_volumes'] = updated
    else:
        terminal['docker_volumes'] = [desired]
    return config


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-root', default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument('--base', default=None)
    parser.add_argument('--env-id', required=True)
    parser.add_argument('--profile', default='default')
    parser.add_argument('--output')
    parser.add_argument('--target-home', default=os.environ.get('HOME'))
    parser.add_argument('--print-meta')
    parser.add_argument('--print-service-url')
    parser.add_argument('--service-mode', choices=['auto', 'local', 'remote'], default='auto')
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    base_path = Path(args.base) if args.base else repo_root / 'config' / 'base.yaml'
    env_path = repo_root / 'config' / 'env' / f'{args.env_id}.yaml'

    base = load_yaml(base_path, target_home=args.target_home)
    manifest = load_yaml(env_path, target_home=args.target_home)

    if args.print_meta:
        value = get_path(manifest, args.print_meta)
        if isinstance(value, (dict, list)):
            print(yaml.safe_dump(value, sort_keys=False).strip())
        else:
            print(value)
        return

    if args.print_service_url:
        services = get_path(manifest, 'env.services')
        if not isinstance(services, dict) or args.print_service_url not in services:
            raise SystemExit(f"Unknown service: {args.print_service_url}")
        service = services[args.print_service_url]
        if not isinstance(service, dict):
            raise SystemExit(f"Expected service mapping for {args.print_service_url}")
        print(select_service_url(service, args.service_mode))
        return

    config_overlay = manifest.get('config') or {}
    if not isinstance(config_overlay, dict):
        raise SystemExit(f"Expected config mapping in {env_path}")

    rendered = deep_merge(base, config_overlay)
    rendered = apply_profile_overrides(rendered, manifest, args.profile)

    output = yaml.safe_dump(rendered, sort_keys=False)
    if args.output:
        Path(args.output).write_text(output)
    else:
        print(output, end='')


if __name__ == '__main__':
    main()
