#!/usr/bin/env python3
"""Render OpenClaw workspace files from YAML configs + Jinja2 templates."""

import argparse
import shutil
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from clawteam_glm.config import discover_agents
from clawteam_glm.renderer import render_all_templates
from clawteam_glm.workspace import apply_workspace_update


def main():
    parser = argparse.ArgumentParser(description="Render workspace files for OpenClaw agents")
    parser.add_argument("--agent", help="Agent role_key to render (e.g., 'assistant')")
    parser.add_argument("--all", action="store_true", help="Render all agents")
    parser.add_argument("--project-dir", default=".", help="Project root directory")
    parser.add_argument("--instance", default="instance.yaml", help="instance.yaml path")
    parser.add_argument("--output", help="Override agents_dir")
    parser.add_argument("--workspace", help="Override target workspace path directly")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()

    if not args.agent and not args.all:
        parser.error("Specify --agent <role_key> or --all")

    agents = discover_agents(project_dir / "agents")

    if args.agent:
        agents = [a for a in agents if a["role_key"] == args.agent]
        if not agents:
            print(f"Error: agent '{args.agent}' not found", file=sys.stderr)
            sys.exit(1)

    instance_path = Path(args.instance)
    if args.output:
        agents_dir = Path(args.output)
    elif instance_path.exists():
        data = yaml.safe_load(instance_path.read_text())
        agents_dir = Path(data["openclaw"]["agents_dir"])
    else:
        print("Error: no --output and instance.yaml not found. Run preflight-check.sh first.", file=sys.stderr)
        sys.exit(1)

    templates_dir = project_dir / "templates"

    for agent in agents:
        role_key = agent["role_key"]
        rendered_dir = project_dir / ".rendered" / role_key
        rendered_dir.mkdir(parents=True, exist_ok=True)

        render_all_templates(project_dir, agent, templates_dir, rendered_dir)

        if args.workspace:
            workspace = Path(args.workspace)
        elif args.output:
            workspace = agents_dir / role_key / "workspace"
        elif instance_path.exists():
            data = yaml.safe_load(instance_path.read_text())
            existing = [a for a in data.get("agents", {}).get("existing", []) if a["role_key"] == role_key]
            if existing:
                workspace = Path(existing[0]["workspace"])
            else:
                workspace = agents_dir / role_key / "workspace"
        else:
            workspace = agents_dir / role_key / "workspace"

        apply_workspace_update(rendered_dir, workspace)
        print(f"Rendered {role_key} -> {workspace}")

        shutil.rmtree(str(rendered_dir), ignore_errors=True)


if __name__ == "__main__":
    main()
