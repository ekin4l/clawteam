# src/clawteam_glm/renderer.py
"""Jinja2 template rendering engine for OpenClaw workspace files."""

from pathlib import Path
from typing import Any

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

from clawteam_glm.config import load_work_item, load_compliance, load_assignments, load_team_members


def build_template_context(project_dir: Path, agent_config: dict[str, Any]) -> dict[str, Any]:
    """Assemble the full template context from all project data sources.

    Loads work items, compliance rules, team members, and collaboration
    entries based on the agent's role_key and project assignments.
    """
    assignments_path = project_dir / "assignments.yaml"
    assignments = load_assignments(assignments_path) if assignments_path.exists() else {}
    role_key = agent_config["role_key"]
    work_item_names = assignments.get("defaults", {}).get(role_key, [])
    work_items = []
    for wi_name in work_item_names:
        wi_path = project_dir / "work_items" / f"{wi_name}.yaml"
        if wi_path.exists():
            work_items.append(load_work_item(wi_path))
    compliance_path = project_dir / "compliance.yaml"
    compliance = load_compliance(compliance_path) if compliance_path.exists() else {"version": "1.0", "rules": {}}
    team = load_team_members(project_dir / "team")
    collaboration = [c for c in assignments.get("collaboration", []) if role_key in c.get("agents", [])]
    return {"agent": agent_config, "work_items": work_items, "compliance": compliance, "team": team, "collaboration": collaboration}


def render_template(template_path: Path, context: dict[str, Any]) -> str:
    """Render a single Jinja2 template file with the given context.

    Uses StrictUndefined so that references to undefined variables raise
    an error rather than rendering silently as empty string.
    """
    env = Environment(loader=FileSystemLoader(str(template_path.parent)), undefined=StrictUndefined, keep_trailing_newline=True)
    template = env.get_template(template_path.name)
    return template.render(**context)


def render_all_templates(project_dir: Path, agent_config: dict[str, Any], templates_dir: Path, output_dir: Path) -> None:
    """Discover all ``*.tmpl`` files in *templates_dir*, render each, and write results to *output_dir*.

    Output filenames are derived from the template stem (e.g. ``SOUL.md.tmpl`` -> ``SOUL.md``).
    The *output_dir* is created if it does not already exist.
    """
    context = build_template_context(project_dir, agent_config)
    output_dir.mkdir(parents=True, exist_ok=True)
    for tmpl_file in sorted(templates_dir.glob("*.tmpl")):
        content = render_template(tmpl_file, context)
        output_name = tmpl_file.stem
        (output_dir / output_name).write_text(content, encoding="utf-8")
