# src/clawteam_glm/config.py
"""Load and validate YAML configuration files."""

from pathlib import Path
from typing import Any

import yaml


_REQUIRED_AGENT_FIELDS = ["role_key", "display_name", "personality"]
_REQUIRED_WORK_ITEM_FIELDS = ["name"]


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data or {}


def _validate_required(data: dict, fields: list[str], context: str) -> None:
    for field in fields:
        if field not in data:
            raise ValueError(f"Missing required field '{field}' in {context}")


def load_agent_config(path: Path) -> dict[str, Any]:
    data = _load_yaml(path)
    _validate_required(data, _REQUIRED_AGENT_FIELDS, f"agent: {path.name}")
    return data


def discover_agents(agents_dir: Path) -> list[dict[str, Any]]:
    if not agents_dir.exists():
        return []
    agents = []
    for f in sorted(agents_dir.glob("*.yaml")):
        if f.name.startswith("_"):
            continue
        agents.append(load_agent_config(f))
    return agents


def load_work_item(path: Path) -> dict[str, Any]:
    data = _load_yaml(path)
    _validate_required(data, _REQUIRED_WORK_ITEM_FIELDS, f"work item: {path.name}")
    return data


def load_compliance(path: Path) -> dict[str, Any]:
    return _load_yaml(path)


def load_assignments(path: Path) -> dict[str, Any]:
    return _load_yaml(path)


def load_team_members(team_dir: Path) -> list[dict[str, Any]]:
    if not team_dir.exists():
        return []
    members = []
    for f in sorted(team_dir.glob("*.yaml")):
        if f.name.startswith("_"):
            continue
        members.append(_load_yaml(f))
    return members


def load_tools(tools_dir: Path) -> list[dict[str, Any]]:
    if not tools_dir.exists():
        return []
    tools = []
    for f in sorted(tools_dir.rglob("*.yaml")):
        if f.name.startswith("_"):
            continue
        tools.append(_load_yaml(f))
    return tools


def load_storage(path: Path) -> dict[str, Any]:
    """Load storage configuration (Feishu Drive folder tokens etc.)."""
    return _load_yaml(path)


def resolve_output_storage(
    work_item: dict[str, Any], storage: dict[str, Any]
) -> dict[str, Any] | None:
    """Resolve a work item's output_config against storage.yaml.

    Returns a dict with resolved directory info, or None if no output_config.
    """
    output_config = work_item.get("output_config")
    if not output_config:
        return None

    storage_ref = output_config.get("storage_ref", "")
    dir_key = output_config.get("dir_key", "")

    result = {
        "storage_ref": storage_ref,
        "dir_key": dir_key,
        "file_templates": {
            k: v for k, v in output_config.items()
            if k.endswith("_file")
        },
        "per_person_dir": output_config.get("per_person_dir", False),
    }

    # Resolve the target directory from storage config
    if storage_ref and dir_key:
        storage_section = storage.get(storage_ref, {})
        root = storage_section.get("root_folder_token", "")
        dirs = storage_section.get("dirs", {})
        result["root_folder_token"] = root
        result["target_dir"] = dirs.get(dir_key, dir_key)

    return result
