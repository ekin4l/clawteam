# tests/test_integration.py
"""End-to-end integration tests."""

import yaml
from pathlib import Path

import pytest
from clawteam_glm.config import discover_agents, load_compliance, load_assignments
from clawteam_glm.renderer import render_all_templates
from clawteam_glm.workspace import apply_workspace_update
from clawteam_glm.memory import export_memory, import_memory


class TestFullPipeline:
    """Test the complete config -> render -> workspace -> memory pipeline."""

    def test_full_pipeline_for_assistant(
        self, tmp_path,
        sample_agent_yaml, sample_work_item_yaml,
        sample_compliance_yaml, sample_assignments_yaml,
        sample_team_member_yaml,
    ):
        # 1. Write all config files
        (tmp_path / "agents").mkdir()
        (tmp_path / "work_items").mkdir()
        (tmp_path / "team").mkdir()
        (tmp_path / "agents" / "assistant_nora.yaml").write_text(yaml.dump(sample_agent_yaml))
        (tmp_path / "work_items" / "daily_report.yaml").write_text(yaml.dump(sample_work_item_yaml))
        (tmp_path / "work_items" / "meeting_minutes.yaml").write_text(yaml.dump({
            "name": "meeting_minutes",
            "display_name": "会议纪要整理",
            "description": "整理会议纪要并分发",
            "category": "communication",
        }))
        (tmp_path / "compliance.yaml").write_text(yaml.dump(sample_compliance_yaml))
        (tmp_path / "assignments.yaml").write_text(yaml.dump(sample_assignments_yaml))
        (tmp_path / "team" / "yang_xiaohua.yaml").write_text(yaml.dump(sample_team_member_yaml))

        # 2. Write templates
        templates = tmp_path / "templates"
        templates.mkdir()
        (templates / "SOUL.md.tmpl").write_text(
            "# SOUL\n{{ agent.personality }}\n\n## Boundaries\n"
            "{% for t in compliance.rules.avoid_topics %}- {{ t }}\n{% endfor %}"
        )
        (templates / "AGENTS.md.tmpl").write_text(
            "# AGENTS\n{% for wi in work_items %}## {{ wi.display_name }}\n{{ wi.description }}\n{% endfor %}"
        )
        (templates / "IDENTITY.md.tmpl").write_text("- **Name:** {{ agent.display_name }}\n- **Emoji:** {{ agent.emoji }}")
        (templates / "HEARTBEAT.md.tmpl").write_text("{% for t in agent.heartbeat_tasks %}- [ ] {{ t }}\n{% endfor %}")
        (templates / "TOOLS.md.tmpl").write_text("# TOOLS\n\n## Managed by system")
        (templates / "TEAM.md.tmpl").write_text("# TEAM\n{% for m in team %}## {{ m.name }}\n{% endfor %}")

        # 3. Discover and render
        agents = discover_agents(tmp_path / "agents")
        assert len(agents) == 1
        agent = agents[0]
        rendered_dir = tmp_path / "rendered"
        render_all_templates(tmp_path, agent, templates, rendered_dir)

        # 4. Verify rendered files
        assert "Nora" in (rendered_dir / "SOUL.md").read_text()
        assert "不讨论公司财务数据" in (rendered_dir / "SOUL.md").read_text()
        assert "🌸" in (rendered_dir / "IDENTITY.md").read_text()
        assert "日报收集整理" in (rendered_dir / "AGENTS.md").read_text()

        # 5. Apply to workspace (with existing memory)
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("precious agent memory")
        (workspace / "TOOLS.md").write_text("# TOOLS\n\n## Agent Notes\n- my note")

        apply_workspace_update(rendered_dir, workspace)

        # 6. Verify workspace
        assert "Nora" in (workspace / "SOUL.md").read_text()  # overwritten
        assert (workspace / "MEMORY.md").read_text() == "precious agent memory"  # preserved
        tools = (workspace / "TOOLS.md").read_text()
        assert "Managed by system" in tools  # merged template
        assert "Agent Notes" in tools  # preserved agent notes

        # 7. Export memory
        backup = tmp_path / "backup"
        export_memory(workspace, backup_dir=backup / "assistant")
        assert (backup / "assistant" / "MEMORY.md").read_text() == "precious agent memory"

        # 8. Import memory to new workspace
        new_workspace = tmp_path / "new_workspace"
        new_workspace.mkdir()
        import_memory(backup / "assistant", new_workspace)
        assert (new_workspace / "MEMORY.md").read_text() == "precious agent memory"

    def test_full_pipeline_with_tar_archive_roundtrip(
        self, tmp_path,
        sample_agent_yaml, sample_work_item_yaml,
        sample_compliance_yaml, sample_assignments_yaml,
        sample_team_member_yaml,
    ):
        """Test export to tar archive and import back."""
        # Set up project
        (tmp_path / "agents").mkdir()
        (tmp_path / "work_items").mkdir()
        (tmp_path / "team").mkdir()
        (tmp_path / "agents" / "assistant_nora.yaml").write_text(yaml.dump(sample_agent_yaml))
        (tmp_path / "work_items" / "daily_report.yaml").write_text(yaml.dump(sample_work_item_yaml))
        (tmp_path / "compliance.yaml").write_text(yaml.dump(sample_compliance_yaml))
        (tmp_path / "assignments.yaml").write_text(yaml.dump(sample_assignments_yaml))
        (tmp_path / "team" / "yang_xiaohua.yaml").write_text(yaml.dump(sample_team_member_yaml))

        templates = tmp_path / "templates"
        templates.mkdir()
        (templates / "SOUL.md.tmpl").write_text("{{ agent.personality }}")
        (templates / "IDENTITY.md.tmpl").write_text("{{ agent.display_name }}")
        (templates / "TOOLS.md.tmpl").write_text("# TOOLS")

        # Render
        agents = discover_agents(tmp_path / "agents")
        rendered_dir = tmp_path / "rendered"
        render_all_templates(tmp_path, agents[0], templates, rendered_dir)

        # Create workspace with memory
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("tar test memory")
        (workspace / "memory").mkdir()
        (workspace / "memory" / "2026-05-05.md").write_text("daily note")
        apply_workspace_update(rendered_dir, workspace)

        # Export to tar archive
        archive_path = tmp_path / "backup.tar.gz"
        export_memory(workspace, archive_path=archive_path)
        assert archive_path.exists()

        # Import from tar archive to fresh workspace
        fresh_workspace = tmp_path / "fresh_workspace"
        fresh_workspace.mkdir()
        import_memory(archive_path, fresh_workspace)
        assert (fresh_workspace / "MEMORY.md").read_text() == "tar test memory"

    def test_pipeline_preserves_user_file(self, tmp_path, sample_agent_yaml):
        """USER.md is a protected file that must survive workspace updates."""
        (tmp_path / "agents").mkdir()
        (tmp_path / "agents" / "assistant_nora.yaml").write_text(yaml.dump(sample_agent_yaml))
        (tmp_path / "compliance.yaml").write_text(yaml.dump({"version": "1.0", "rules": {}}))
        (tmp_path / "assignments.yaml").write_text(yaml.dump({"defaults": {"assistant": []}}))

        templates = tmp_path / "templates"
        templates.mkdir()
        (templates / "SOUL.md.tmpl").write_text("soul content")
        (templates / "USER.md.tmpl").write_text("template user content")

        agents = discover_agents(tmp_path / "agents")
        rendered_dir = tmp_path / "rendered"
        render_all_templates(tmp_path, agents[0], templates, rendered_dir)

        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "USER.md").write_text("existing user data")

        apply_workspace_update(rendered_dir, workspace)

        assert (workspace / "USER.md").read_text() == "existing user data"


class TestConfigValidation:
    """Test that all shipped YAML configs are valid."""

    def test_all_agent_configs_load(self):
        project_dir = Path(__file__).resolve().parent.parent
        agents_dir = project_dir / "agents"
        if not agents_dir.exists():
            pytest.skip("agents/ directory not yet created")

        agents = discover_agents(agents_dir)
        assert len(agents) == 5
        role_keys = {a["role_key"] for a in agents}
        assert role_keys == {"assistant", "architect", "quality", "ops", "tester"}

    def test_compliance_loads(self):
        project_dir = Path(__file__).resolve().parent.parent
        comp_path = project_dir / "compliance.yaml"
        if not comp_path.exists():
            pytest.skip("compliance.yaml not yet created")

        data = load_compliance(comp_path)
        assert "rules" in data

    def test_assignments_loads(self):
        project_dir = Path(__file__).resolve().parent.parent
        asgn_path = project_dir / "assignments.yaml"
        if not asgn_path.exists():
            pytest.skip("assignments.yaml not yet created")

        data = load_assignments(asgn_path)
        assert "defaults" in data
        assert len(data["defaults"]) == 5
