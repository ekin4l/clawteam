"""Detect OpenClaw instance configuration (supports cloud vendor variants)."""

import re
import subprocess
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

import yaml


@dataclass
class InstanceInfo:
    version: str
    variant: str = "standard"
    state_dir: Path = Path()
    config_path: Path = Path()
    workspace_root: Path = Path()
    agents_dir: Path = Path()
    capabilities: dict = field(default_factory=lambda: {
        "multi_agent": True, "agents_add": True,
        "agents_bind": True, "agents_set_identity": True,
    })
    existing_agents: list = field(default_factory=list)


def detect_openclaw_version() -> str | None:
    try:
        result = subprocess.run(
            ["openclaw", "--version"], capture_output=True, text=True, timeout=10,
        )
        match = re.search(r"(\d{4}\.\d+\.\d+)", result.stdout)
        return match.group(1) if match else None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def detect_state_dir() -> Path | None:
    candidates = [Path.home() / ".openclaw", Path.home() / ".openclaw-dev"]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def _detect_variant(config_path: Path) -> str:
    if not config_path.exists():
        return "standard"
    try:
        text = config_path.read_text(encoding="utf-8")
        if "huawei" in text.lower() or "codearts" in text.lower():
            return "huawei"
        if "aliyun" in text.lower():
            return "aliyun"
    except Exception:
        pass
    return "standard"


def _list_existing_agents(agents_dir: Path) -> list[dict]:
    if not agents_dir.exists():
        return []
    agents = []
    for d in sorted(agents_dir.iterdir()):
        if d.is_dir() and not d.name.startswith("."):
            agents.append({
                "role_key": d.name,
                "workspace": str(d / "workspace") if (d / "workspace").exists() else str(d),
            })
    return agents


def detect_instance(output_path: Path | None = None) -> InstanceInfo:
    state_dir = detect_state_dir()
    if state_dir is None:
        raise RuntimeError("OpenClaw state directory not found. Ensure OpenClaw is installed and initialized.")
    version = detect_openclaw_version() or "unknown"
    config_path = state_dir / "openclaw.json"
    workspace_root = state_dir / "workspace"
    agents_dir = state_dir / "agents"
    variant = _detect_variant(config_path)
    existing_agents = _list_existing_agents(agents_dir)

    info = InstanceInfo(
        version=version, variant=variant, state_dir=state_dir,
        config_path=config_path, workspace_root=workspace_root,
        agents_dir=agents_dir, existing_agents=existing_agents,
    )
    if output_path is not None:
        _write_instance_yaml(info, output_path)
    return info


def _write_instance_yaml(info: InstanceInfo, path: Path) -> None:
    data = {
        "detected_at": date.today().isoformat(),
        "openclaw": {
            "version": info.version, "variant": info.variant,
            "state_dir": str(info.state_dir), "config_path": str(info.config_path),
            "workspace_root": str(info.workspace_root), "agents_dir": str(info.agents_dir),
        },
        "capabilities": info.capabilities,
        "agents": {"existing": info.existing_agents},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True))
