# tests/test_workspace.py
from pathlib import Path

import pytest
from clawteam_glm.workspace import (
    apply_workspace_update,
    merge_tools_md,
    PROTECTED_FILES,
)


class TestApplyWorkspaceUpdate:
    def test_overwrites_config_files(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "SOUL.md").write_text("old content")
        source = tmp_path / "rendered"
        source.mkdir()
        (source / "SOUL.md").write_text("new content")
        apply_workspace_update(source, workspace)
        assert (workspace / "SOUL.md").read_text() == "new content"

    def test_preserves_memory_files(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("precious memory")
        (workspace / "USER.md").write_text("user info")
        (workspace / "memory").mkdir()
        (workspace / "memory" / "2026-05-05.md").write_text("daily log")
        source = tmp_path / "rendered"
        source.mkdir()
        apply_workspace_update(source, workspace)
        assert (workspace / "MEMORY.md").read_text() == "precious memory"
        assert (workspace / "USER.md").read_text() == "user info"
        assert (workspace / "memory" / "2026-05-05.md").read_text() == "daily log"

    def test_merges_tools_md(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "TOOLS.md").write_text("# TOOLS\n\n## Agent Notes\n- My custom note\n")
        source = tmp_path / "rendered"
        source.mkdir()
        (source / "TOOLS.md").write_text("# TOOLS\n\n## CodeArts\n- Issue CRUD\n")
        apply_workspace_update(source, workspace)
        result = (workspace / "TOOLS.md").read_text()
        assert "CodeArts" in result
        assert "Agent Notes" in result

    def test_creates_new_files(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        source = tmp_path / "rendered"
        source.mkdir()
        (source / "IDENTITY.md").write_text("- **Name:** Nora")
        apply_workspace_update(source, workspace)
        assert (workspace / "IDENTITY.md").exists()
        assert "Nora" in (workspace / "IDENTITY.md").read_text()


class TestMergeToolsMd:
    def test_merges_template_content_with_agent_notes(self):
        existing = "# TOOLS\n\n## Agent Notes\n- custom\n"
        template = "# TOOLS\n\n## CodeArts\n- Issue CRUD\n"
        result = merge_tools_md(existing, template)
        assert "CodeArts" in result
        assert "Agent Notes" in result

    def test_no_duplicate_sections(self):
        existing = "# TOOLS\n\n## CodeArts\n- old note\n"
        template = "# TOOLS\n\n## CodeArts\n- Issue CRUD\n"
        result = merge_tools_md(existing, template)
        assert result.count("## CodeArts") == 1

    def test_empty_existing_uses_template(self):
        template = "# TOOLS\n\n## CodeArts\n- Issue CRUD\n"
        result = merge_tools_md("", template)
        assert "CodeArts" in result


class TestProtectedFiles:
    def test_memory_files_are_protected(self):
        assert "MEMORY.md" in PROTECTED_FILES
        assert "USER.md" in PROTECTED_FILES

    def test_config_files_are_not_protected(self):
        assert "SOUL.md" not in PROTECTED_FILES
        assert "AGENTS.md" not in PROTECTED_FILES
        assert "IDENTITY.md" not in PROTECTED_FILES
