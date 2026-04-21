#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Any

import yaml


DEFAULT_CLOUD_MODEL = "qwen3-coder:480b-cloud"
DEFAULT_CUSTOM_PROVIDER = "local-ollama"


def env_flag(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def load_yaml(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text()) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"Expected top-level mapping in {path}")
    return data


def save_yaml(path: Path, data: dict[str, Any]) -> None:
    path.write_text(yaml.safe_dump(data, sort_keys=False))


def ensure_custom_provider(cfg: dict[str, Any], *, name: str, base_url: str, api_key: str | None) -> None:
    providers = cfg.get("custom_providers")
    if providers is None:
        providers = []
        cfg["custom_providers"] = providers
    if not isinstance(providers, list):
        raise SystemExit("custom_providers must be a list")

    normalized_name = name.strip()
    target: dict[str, Any] | None = None
    for entry in providers:
        if not isinstance(entry, dict):
            continue
        if str(entry.get("name", "")).strip().lower() == normalized_name.lower():
            target = entry
            break

    if target is None:
        target = {"name": normalized_name}
        providers.append(target)

    target["base_url"] = base_url
    target["api_mode"] = "chat_completions"
    if api_key:
        target["api_key"] = api_key
    else:
        target.pop("api_key", None)



def apply_cloud_strategy(cfg: dict[str, Any]) -> str:
    delegation_model = os.getenv("HERMES_OLLAMA_DELEGATION_MODEL", DEFAULT_CLOUD_MODEL).strip()
    fallback_model = os.getenv("HERMES_OLLAMA_FALLBACK_MODEL", delegation_model).strip()
    cheap_model = os.getenv("HERMES_OLLAMA_CHEAP_MODEL", "").strip()

    cfg["fallback_model"] = {
        "provider": "ollama-cloud",
        "model": fallback_model,
    }

    delegation = cfg.setdefault("delegation", {})
    if not isinstance(delegation, dict):
        raise SystemExit("delegation must be a mapping")
    delegation["provider"] = "ollama-cloud"
    delegation["model"] = delegation_model
    delegation["base_url"] = ""
    delegation["api_key"] = ""

    if env_flag("HERMES_OLLAMA_ENABLE_SMART_ROUTING", default=False) and cheap_model:
        smart = cfg.setdefault("smart_model_routing", {})
        if not isinstance(smart, dict):
            raise SystemExit("smart_model_routing must be a mapping")
        smart["enabled"] = True
        smart.setdefault("max_simple_chars", 160)
        smart.setdefault("max_simple_words", 28)
        smart["cheap_model"] = {"provider": "ollama-cloud", "model": cheap_model}

    return f"cloud(provider=ollama-cloud delegation={delegation_model} fallback={fallback_model})"



def apply_custom_strategy(cfg: dict[str, Any]) -> str:
    base_url = os.getenv("HERMES_OLLAMA_BASE_URL", "").strip()
    if not base_url:
        raise SystemExit("HERMES_OLLAMA_BASE_URL is required for custom/local Ollama strategy")

    provider_name = os.getenv("HERMES_OLLAMA_PROVIDER_NAME", DEFAULT_CUSTOM_PROVIDER).strip() or DEFAULT_CUSTOM_PROVIDER
    shared_model = os.getenv("HERMES_OLLAMA_MODEL", "").strip()
    delegation_model = os.getenv("HERMES_OLLAMA_DELEGATION_MODEL", shared_model).strip()
    fallback_model = os.getenv("HERMES_OLLAMA_FALLBACK_MODEL", shared_model or delegation_model).strip()
    endpoint_api_key = os.getenv("HERMES_OLLAMA_ENDPOINT_API_KEY", "").strip()

    if not delegation_model or not fallback_model:
        raise SystemExit(
            "Custom/local Ollama strategy requires HERMES_OLLAMA_MODEL or both "
            "HERMES_OLLAMA_DELEGATION_MODEL and HERMES_OLLAMA_FALLBACK_MODEL"
        )

    ensure_custom_provider(cfg, name=provider_name, base_url=base_url, api_key=endpoint_api_key or None)

    cfg["fallback_model"] = {
        "provider": "custom",
        "model": fallback_model,
        "base_url": base_url,
        "api_key": endpoint_api_key,
    }

    delegation = cfg.setdefault("delegation", {})
    if not isinstance(delegation, dict):
        raise SystemExit("delegation must be a mapping")
    delegation["provider"] = "custom"
    delegation["model"] = delegation_model
    delegation["base_url"] = base_url
    delegation["api_key"] = endpoint_api_key

    if env_flag("HERMES_OLLAMA_ENABLE_SMART_ROUTING", default=False):
        cheap_model = os.getenv("HERMES_OLLAMA_CHEAP_MODEL", shared_model or delegation_model).strip()
        if cheap_model:
            smart = cfg.setdefault("smart_model_routing", {})
            if not isinstance(smart, dict):
                raise SystemExit("smart_model_routing must be a mapping")
            smart["enabled"] = True
            smart.setdefault("max_simple_chars", 160)
            smart.setdefault("max_simple_words", 28)
            smart["cheap_model"] = {
                "provider": "custom",
                "model": cheap_model,
                "base_url": base_url,
                "api_key": endpoint_api_key,
            }

    return f"custom(provider={provider_name} base_url={base_url} delegation={delegation_model} fallback={fallback_model})"



def main() -> None:
    parser = argparse.ArgumentParser(description="Apply optional Hermes model strategy overrides to a rendered config.yaml")
    parser.add_argument("config_path", help="Rendered Hermes config.yaml path")
    args = parser.parse_args()

    path = Path(args.config_path)
    if not path.exists():
        raise SystemExit(f"Config file not found: {path}")

    cloud_key = os.getenv("OLLAMA_API_KEY", "").strip()
    custom_base_url = os.getenv("HERMES_OLLAMA_BASE_URL", "").strip()

    if custom_base_url:
        strategy_mode = "custom"
    elif cloud_key:
        strategy_mode = "cloud"
    else:
        print(f"No Ollama strategy env configured for {path}; leaving rendered config unchanged.")
        return

    cfg = load_yaml(path)
    summary = apply_custom_strategy(cfg) if strategy_mode == "custom" else apply_cloud_strategy(cfg)
    save_yaml(path, cfg)
    print(f"Applied Ollama strategy to {path}: {summary}")


if __name__ == "__main__":
    main()
