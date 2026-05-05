# src/clawteam_glm/workspace.py
"""Workspace file management with update policies."""

import shutil
from pathlib import Path

PROTECTED_FILES = {"MEMORY.md", "USER.md"}
PROTECTED_DIRS = {"memory"}
MERGE_FILES = {"TOOLS.md"}


def merge_tools_md(existing: str, template: str) -> str:
    if not existing.strip():
        return template

    def parse_sections(text: str) -> dict[str, str]:
        sections = {}
        current_heading = "_preamble"
        current_lines = []
        for line in text.split("\n"):
            if line.startswith("## "):
                if current_lines:
                    sections[current_heading] = "\n".join(current_lines)
                current_heading = line.strip()
                current_lines = [line]
            else:
                current_lines.append(line)
        if current_lines:
            sections[current_heading] = "\n".join(current_lines)
        return sections

    existing_sections = parse_sections(existing)
    template_sections = parse_sections(template)
    merged = {**existing_sections, **template_sections}

    order = []
    if "_preamble" in merged:
        order.append("_preamble")
    for key in sorted(k for k in merged if k != "_preamble"):
        order.append(key)
    return "\n".join(merged[k] for k in order)


def apply_workspace_update(source_dir: Path, workspace_dir: Path) -> None:
    workspace_dir.mkdir(parents=True, exist_ok=True)
    for source_file in source_dir.iterdir():
        if source_file.is_dir():
            continue
        filename = source_file.name
        if filename in PROTECTED_FILES:
            continue
        target = workspace_dir / filename
        if filename in MERGE_FILES and target.exists():
            existing = target.read_text(encoding="utf-8")
            template = source_file.read_text(encoding="utf-8")
            merged = merge_tools_md(existing, template)
            target.write_text(merged, encoding="utf-8")
        else:
            shutil.copy2(str(source_file), str(target))
