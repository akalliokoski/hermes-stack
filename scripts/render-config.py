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


def first_present(service: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = service.get(key)
        if value:
            return str(value)
    return None


def select_service_url(service: dict[str, Any], service_mode: str) -> str:
    local_keys = (
        'local_api_url',
        'api_url',
        'optional_local_api_url',
        'local_gui_url',
        'gui_url',
        'optional_local_gui_url',
        'local_ui_url',
        'ui_url',
        'optional_local_ui_url',
        'landing_url',
    )
    remote_keys = (
        'remote_api_url',
        'api_url',
        'optional_remote_api_url',
        'remote_gui_url',
        'gui_url',
        'optional_remote_gui_url',
        'remote_ui_url',
        'ui_url',
        'optional_remote_ui_url',
        'landing_url',
    )

    if service_mode == 'local':
        selected = first_present(service, *local_keys)
        if selected:
            return selected
    elif service_mode in ('remote', 'auto'):
        if service_mode == 'auto' and str(service.get('mode', '')).startswith('local'):
            selected = first_present(service, *local_keys)
            if selected:
                return selected
        selected = first_present(service, *remote_keys)
        if selected:
            return selected
        if service_mode == 'auto':
            selected = first_present(service, *local_keys)
            if selected:
                return selected
    raise SystemExit(f"Could not determine service URL for mode={service_mode!r} service={service}")


def append_unique(items: list[str], value: str) -> list[str]:
    if value not in items:
        items.append(value)
    return items


def apply_manifest_profile_overrides(config: dict[str, Any], manifest: dict[str, Any], profile: str) -> dict[str, Any]:
    overrides = manifest.get('profile_overrides') or {}
    if not isinstance(overrides, dict):
        raise SystemExit('Expected profile_overrides to be a mapping when present')
    override = overrides.get(profile)
    if override is None:
        return config
    if not isinstance(override, dict):
        raise SystemExit(f'Expected profile_overrides.{profile} to be a mapping')
    return deep_merge(config, override)


def apply_profile_overrides(config: dict[str, Any], manifest: dict[str, Any], profile: str) -> dict[str, Any]:
    work_root = get_path(manifest, 'env.work_root')
    profile_root = Path(get_path(manifest, 'env.profile_root'))
    host_home = str(profile_root.parent)
    env_role = str(get_path(manifest, 'env.role'))
    terminal = config.setdefault('terminal', {})
    profile_workspace = f"{work_root}/{profile}"

    if env_role == 'service-host':
        terminal['backend'] = 'local'
        terminal['cwd'] = profile_workspace
        terminal['docker_env'] = {}
        terminal['docker_volumes'] = []
        terminal['docker_forward_env'] = []
        return config

    docker_volumes = terminal.get('docker_volumes')
    workspace_mount = f"{profile_workspace}:/workspace"
    if docker_volumes is None:
        updated_volumes = [workspace_mount]
    elif isinstance(docker_volumes, list):
        updated_volumes = []
        replaced = False
        for entry in docker_volumes:
            entry_str = str(entry)
            if entry_str.endswith(':/workspace') and not replaced:
                updated_volumes.append(workspace_mount)
                replaced = True
            else:
                updated_volumes.append(entry_str)
        if not replaced:
            updated_volumes.append(workspace_mount)
    else:
        updated_volumes = [workspace_mount]

    git_runtime_mounts = [
        f"{host_home}/.gitconfig:/home/hermes/.gitconfig:ro",
        f"{host_home}/.config/git:/home/hermes/.config/git:ro",
        f"{host_home}/.ssh:/home/hermes/.ssh:ro",
        f"{host_home}/.gitconfig:/root/.gitconfig:ro",
        f"{host_home}/.config/git:/root/.config/git:ro",
        f"{host_home}/.ssh:/root/.ssh:ro",
    ]
    for mount in git_runtime_mounts:
        append_unique(updated_volumes, mount)
    terminal['docker_volumes'] = updated_volumes

    docker_env = terminal.get('docker_env')
    if not isinstance(docker_env, dict):
        docker_env = {}
    docker_env.setdefault('HOME', '/home/hermes')
    terminal['docker_env'] = docker_env
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
    rendered = apply_manifest_profile_overrides(rendered, manifest, args.profile)

    output = yaml.safe_dump(rendered, sort_keys=False)
    if args.output:
        Path(args.output).write_text(output)
    else:
        print(output, end='')


if __name__ == '__main__':
    main()
