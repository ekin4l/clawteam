# tests/test_renderer.py
import yaml
from pathlib import Path

import pytest
from clawteam_glm.renderer import (
    build_template_context,
    render_template,
    render_all_templates,
)


class TestBuildTemplateContext:
    def test_assembles_context_from_all_sources(
        self, tmp_project, sample_agent_yaml,
        sample_work_item_yaml, sample_compliance_yaml,
        sample_assignments_yaml, sample_team_member_yaml,
    ):
        (tmp_project / "agents" / "assistant_nora.yaml").write_text(yaml.dump(sample_agent_yaml))
        (tmp_project / "work_items" / "daily_report.yaml").write_text(yaml.dump(sample_work_item_yaml))
        (tmp_project / "work_items" / "meeting_minutes.yaml").write_text(yaml.dump({
            "name": "meeting_minutes",
            "display_name": "会议纪要整理",
            "category": "communication",
        }))
        (tmp_project / "compliance.yaml").write_text(yaml.dump(sample_compliance_yaml))
        (tmp_project / "assignments.yaml").write_text(yaml.dump(sample_assignments_yaml))
        (tmp_project / "team" / "yang_xiaohua.yaml").write_text(yaml.dump(sample_team_member_yaml))

        ctx = build_template_context(project_dir=tmp_project, agent_config=sample_agent_yaml)

        assert ctx["agent"]["role_key"] == "assistant"
        assert ctx["agent"]["display_name"] == "Nora"
        assert len(ctx["work_items"]) == 2
        assert ctx["work_items"][0]["name"] == "daily_report"
        assert ctx["work_items"][1]["name"] == "meeting_minutes"
        assert "avoid_topics" in ctx["compliance"]["rules"]
        assert len(ctx["team"]) == 1
        assert ctx["team"][0]["name"] == "杨小华"
        assert len(ctx["collaboration"]) == 1

    def test_empty_team_and_compliance_ok(self, tmp_project, sample_agent_yaml):
        (tmp_project / "compliance.yaml").write_text(yaml.dump({"version": "1.0", "rules": {}}))
        (tmp_project / "assignments.yaml").write_text(yaml.dump({"defaults": {"assistant": []}, "collaboration": []}))

        ctx = build_template_context(project_dir=tmp_project, agent_config=sample_agent_yaml)
        assert ctx["team"] == []
        assert ctx["work_items"] == []


class TestRenderTemplate:
    def test_renders_identity_template(self, tmp_project, sample_agent_yaml):
        tmpl = tmp_project / "templates" / "IDENTITY.md.tmpl"
        tmpl.write_text("# IDENTITY.md\n- **Name:** {{ agent.display_name }}\n- **Emoji:** {{ agent.emoji }}\n")
        ctx = {"agent": sample_agent_yaml}
        result = render_template(tmpl, ctx)
        assert "Nora" in result
        assert "🌸" in result

    def test_renders_heartbeat_template(self, tmp_project, sample_agent_yaml):
        tmpl = tmp_project / "templates" / "HEARTBEAT.md.tmpl"
        tmpl.write_text("# HEARTBEAT.md\n{% for task in agent.heartbeat_tasks %}\n- [ ] {{ task }}\n{% endfor %}\n")
        ctx = {"agent": sample_agent_yaml}
        result = render_template(tmpl, ctx)
        assert "- [ ] 工作日 18:00 收集团队日报" in result

    def test_renders_team_template(self, tmp_project, sample_team_member_yaml):
        tmpl = tmp_project / "templates" / "TEAM.md.tmpl"
        tmpl.write_text("# TEAM.md\n{% for member in team %}\n## {{ member.name }}\n- **Role:** {{ member.role }}\n{% endfor %}\n")
        ctx = {"team": [sample_team_member_yaml]}
        result = render_template(tmpl, ctx)
        assert "## 杨小华" in result
        assert "技术负责人" in result


class TestRenderAllTemplates:
    def test_renders_all_templates_for_agent(
        self, tmp_project, sample_agent_yaml,
        sample_work_item_yaml, sample_compliance_yaml,
        sample_assignments_yaml, sample_team_member_yaml,
    ):
        (tmp_project / "agents" / "assistant_nora.yaml").write_text(yaml.dump(sample_agent_yaml))
        (tmp_project / "work_items" / "daily_report.yaml").write_text(yaml.dump(sample_work_item_yaml))
        (tmp_project / "work_items" / "meeting_minutes.yaml").write_text(yaml.dump({
            "name": "meeting_minutes",
            "display_name": "会议纪要整理",
            "category": "communication",
        }))
        (tmp_project / "compliance.yaml").write_text(yaml.dump(sample_compliance_yaml))
        (tmp_project / "assignments.yaml").write_text(yaml.dump(sample_assignments_yaml))
        (tmp_project / "team" / "yang_xiaohua.yaml").write_text(yaml.dump(sample_team_member_yaml))

        templates = tmp_project / "templates"
        (templates / "SOUL.md.tmpl").write_text("# SOUL\n{{ agent.personality }}")
        (templates / "AGENTS.md.tmpl").write_text("# AGENTS\n{% for wi in work_items %}- {{ wi.name }}\n{% endfor %}")
        (templates / "IDENTITY.md.tmpl").write_text("- **Name:** {{ agent.display_name }}")
        (templates / "HEARTBEAT.md.tmpl").write_text("{% for t in agent.heartbeat_tasks %}- {{ t }}\n{% endfor %}")
        (templates / "TOOLS.md.tmpl").write_text("# TOOLS")
        (templates / "TEAM.md.tmpl").write_text("# TEAM\n{% for m in team %}## {{ m.name }}\n{% endfor %}")

        output_dir = tmp_project / "output"
        output_dir.mkdir()

        render_all_templates(project_dir=tmp_project, agent_config=sample_agent_yaml, templates_dir=templates, output_dir=output_dir)

        assert (output_dir / "SOUL.md").exists()
        assert (output_dir / "AGENTS.md").exists()
        assert (output_dir / "IDENTITY.md").exists()
        assert (output_dir / "HEARTBEAT.md").exists()
        assert (output_dir / "TOOLS.md").exists()
        assert (output_dir / "TEAM.md").exists()
        assert "你是 Nora" in (output_dir / "SOUL.md").read_text()
        assert "Nora" in (output_dir / "IDENTITY.md").read_text()
