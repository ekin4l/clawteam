import os
import tempfile
from pathlib import Path

import pytest
import yaml


@pytest.fixture
def tmp_project(tmp_path):
    """Create a minimal project directory structure for testing."""
    (tmp_path / "agents").mkdir()
    (tmp_path / "work_items").mkdir()
    (tmp_path / "tools" / "codearts").mkdir(parents=True)
    (tmp_path / "tools" / "feishu").mkdir(parents=True)
    (tmp_path / "tools" / "git").mkdir(parents=True)
    (tmp_path / "team").mkdir()
    (tmp_path / "templates").mkdir()
    (tmp_path / "memories").mkdir()
    return tmp_path


@pytest.fixture
def sample_agent_yaml():
    return {
        "role_key": "assistant",
        "display_name": "Nora",
        "role_title": "研发助理",
        "creature": "AI assistant",
        "emoji": "🌸",
        "vibe": "warm, organized, proactive",
        "avatar": "avatars/nora.svg",
        "model": "zai/glm-4.7",
        "communicates_externally": True,
        "personality": "你是 Nora，一位温暖而高效的研发助理。",
        "assigned_work_items": ["daily_report", "meeting_minutes"],
        "heartbeat_tasks": ["工作日 18:00 收集团队日报"],
        "capabilities": {
            "can_create_feishu_groups": True,
            "can_send_feishu_messages": True,
        },
    }


@pytest.fixture
def sample_work_item_yaml():
    return {
        "name": "daily_report",
        "display_name": "日报收集整理",
        "description": "收集团队成员工作日报",
        "category": "communication",
        "approval_level": "low",
        "tools": ["feishu/messaging"],
        "triggers": {
            "scheduled": "0 18 * * 1-5",
            "manual": "@Nora 日报",
        },
        "inputs": ["团队成员飞书消息"],
        "outputs": ["结构化日报"],
    }


@pytest.fixture
def sample_compliance_yaml():
    return {
        "version": "1.0",
        "rules": {
            "avoid_topics": ["不讨论公司财务数据"],
            "content_policy": ["所有对外沟通需专业、礼貌"],
            "data_handling": ["不将代码内容发送到非工作群"],
        },
    }


@pytest.fixture
def sample_assignments_yaml():
    return {
        "defaults": {
            "assistant": ["daily_report", "meeting_minutes"],
            "architect": ["architecture_design"],
        },
        "collaboration": [
            {
                "trigger": "code_review",
                "action": "group_facilitation",
                "agents": ["quality", "assistant"],
            },
        ],
    }


@pytest.fixture
def sample_instance_yaml():
    return {
        "detected_at": "2026-05-05",
        "openclaw": {
            "version": "2026.5.4",
            "variant": "standard",
            "state_dir": "/tmp/fake-openclaw",
            "config_path": "/tmp/fake-openclaw/openclaw.json",
            "workspace_root": "/tmp/fake-openclaw/workspace",
            "agents_dir": "/tmp/fake-openclaw/agents",
        },
        "capabilities": {
            "multi_agent": True,
            "agents_add": True,
        },
        "agents": {
            "existing": [
                {"role_key": "main", "workspace": "/tmp/fake-openclaw/workspace", "model": "zai/glm-4.7"},
            ],
        },
    }


@pytest.fixture
def sample_team_member_yaml():
    return {
        "name": "杨小华",
        "feishu_id": "ou_xxx",
        "role": "技术负责人",
        "responsibilities": ["网关架构设计"],
        "goals": ["Q2 完成网关性能优化"],
        "modules": ["网关", "APISIX"],
        "notes": "偏好先看数据再讨论方案",
    }
