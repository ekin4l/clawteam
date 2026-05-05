# tests/test_config.py
import yaml
from pathlib import Path

import pytest
from clawteam_glm.config import (
    load_agent_config,
    load_work_item,
    load_compliance,
    load_assignments,
    load_team_members,
    load_tools,
    discover_agents,
)


class TestLoadAgentConfig:
    def test_loads_valid_agent_yaml(self, tmp_project, sample_agent_yaml):
        agent_file = tmp_project / "agents" / "assistant_nora.yaml"
        agent_file.write_text(yaml.dump(sample_agent_yaml))
        result = load_agent_config(agent_file)
        assert result["role_key"] == "assistant"
        assert result["display_name"] == "Nora"
        assert result["communicates_externally"] is True
        assert "daily_report" in result["assigned_work_items"]

    def test_raises_on_missing_role_key(self, tmp_project, sample_agent_yaml):
        del sample_agent_yaml["role_key"]
        agent_file = tmp_project / "agents" / "bad.yaml"
        agent_file.write_text(yaml.dump(sample_agent_yaml))
        with pytest.raises(ValueError, match="role_key"):
            load_agent_config(agent_file)

    def test_raises_on_missing_display_name(self, tmp_project, sample_agent_yaml):
        del sample_agent_yaml["display_name"]
        agent_file = tmp_project / "agents" / "bad.yaml"
        agent_file.write_text(yaml.dump(sample_agent_yaml))
        with pytest.raises(ValueError, match="display_name"):
            load_agent_config(agent_file)

    def test_raises_on_missing_personality(self, tmp_project, sample_agent_yaml):
        del sample_agent_yaml["personality"]
        agent_file = tmp_project / "agents" / "bad.yaml"
        agent_file.write_text(yaml.dump(sample_agent_yaml))
        with pytest.raises(ValueError, match="personality"):
            load_agent_config(agent_file)

    def test_raises_on_nonexistent_file(self):
        with pytest.raises(FileNotFoundError):
            load_agent_config(Path("/nonexistent/file.yaml"))


class TestDiscoverAgents:
    def test_discovers_all_agent_files(self, tmp_project, sample_agent_yaml):
        for name in ["assistant_nora.yaml", "architect_mark.yaml"]:
            (tmp_project / "agents" / name).write_text(yaml.dump(sample_agent_yaml))
        result = discover_agents(tmp_project / "agents")
        assert len(result) == 2

    def test_skips_template_file(self, tmp_project, sample_agent_yaml):
        (tmp_project / "agents" / "_template.yaml").write_text("role_key: template")
        (tmp_project / "agents" / "assistant_nora.yaml").write_text(yaml.dump(sample_agent_yaml))
        result = discover_agents(tmp_project / "agents")
        assert len(result) == 1


class TestLoadWorkItem:
    def test_loads_valid_work_item(self, tmp_project, sample_work_item_yaml):
        wi_file = tmp_project / "work_items" / "daily_report.yaml"
        wi_file.write_text(yaml.dump(sample_work_item_yaml))
        result = load_work_item(wi_file)
        assert result["name"] == "daily_report"
        assert result["approval_level"] == "low"

    def test_raises_on_missing_name(self, tmp_project, sample_work_item_yaml):
        del sample_work_item_yaml["name"]
        wi_file = tmp_project / "work_items" / "bad.yaml"
        wi_file.write_text(yaml.dump(sample_work_item_yaml))
        with pytest.raises(ValueError, match="name"):
            load_work_item(wi_file)


class TestLoadCompliance:
    def test_loads_compliance(self, tmp_project, sample_compliance_yaml):
        comp_file = tmp_project / "compliance.yaml"
        comp_file.write_text(yaml.dump(sample_compliance_yaml))
        result = load_compliance(comp_file)
        assert "avoid_topics" in result["rules"]
        assert len(result["rules"]["avoid_topics"]) == 1


class TestLoadAssignments:
    def test_loads_assignments(self, tmp_project, sample_assignments_yaml):
        asgn_file = tmp_project / "assignments.yaml"
        asgn_file.write_text(yaml.dump(sample_assignments_yaml))
        result = load_assignments(asgn_file)
        assert "assistant" in result["defaults"]
        assert "daily_report" in result["defaults"]["assistant"]


class TestLoadTeamMembers:
    def test_loads_team_member(self, tmp_project, sample_team_member_yaml):
        member_file = tmp_project / "team" / "yang_xiaohua.yaml"
        member_file.write_text(yaml.dump(sample_team_member_yaml))
        result = load_team_members(tmp_project / "team")
        assert len(result) == 1
        assert result[0]["name"] == "杨小华"

    def test_skips_template(self, tmp_project, sample_team_member_yaml):
        (tmp_project / "team" / "_template.yaml").write_text("name: template")
        (tmp_project / "team" / "yang_xiaohua.yaml").write_text(yaml.dump(sample_team_member_yaml))
        result = load_team_members(tmp_project / "team")
        assert len(result) == 1


class TestLoadTools:
    def test_loads_tools_from_subdirs(self, tmp_project):
        tool = {"name": "codearts_issue_crud", "category": "codearts"}
        (tmp_project / "tools" / "codearts" / "issue_crud.yaml").write_text(yaml.dump(tool))
        result = load_tools(tmp_project / "tools")
        assert len(result) == 1
        assert result[0]["name"] == "codearts_issue_crud"

    def test_resolves_tool_by_path(self, tmp_project):
        tool = {"name": "feishu_messaging", "category": "feishu"}
        (tmp_project / "tools" / "feishu" / "messaging.yaml").write_text(yaml.dump(tool))
        result = load_tools(tmp_project / "tools")
        found = [t for t in result if t["name"] == "feishu_messaging"]
        assert len(found) == 1
