# tests/test_detector.py
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

import yaml
import pytest
from clawteam_glm.detector import (
    detect_openclaw_version,
    detect_state_dir,
    detect_instance,
    InstanceInfo,
)


class TestDetectVersion:
    def test_parses_version_string(self):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(stdout="OpenClaw 2026.5.4 (abc1234)\n", returncode=0)
            version = detect_openclaw_version()
            assert version == "2026.5.4"

    def test_returns_none_on_failure(self):
        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = FileNotFoundError("openclaw not found")
            version = detect_openclaw_version()
            assert version is None


class TestDetectStateDir:
    def test_detects_default_dir(self):
        with patch("pathlib.Path.exists", return_value=True):
            state_dir = detect_state_dir()
            assert state_dir is not None

    def test_returns_none_when_not_found(self):
        with patch("pathlib.Path.exists", return_value=False):
            state_dir = detect_state_dir()
            assert state_dir is None


class TestDetectInstance:
    def test_produces_instance_info(self, tmp_path):
        fake_state = tmp_path / ".openclaw"
        fake_state.mkdir()
        (fake_state / "openclaw.json").write_text('{"version": "1"}')
        (fake_state / "workspace").mkdir()
        (fake_state / "agents").mkdir()

        with patch("clawteam_glm.detector.detect_openclaw_version", return_value="2026.5.4"):
            with patch("clawteam_glm.detector.detect_state_dir", return_value=fake_state):
                info = detect_instance()

        assert isinstance(info, InstanceInfo)
        assert info.version == "2026.5.4"
        assert info.state_dir == fake_state

    def test_writes_instance_yaml(self, tmp_path):
        fake_state = tmp_path / ".openclaw"
        fake_state.mkdir()
        (fake_state / "openclaw.json").write_text('{}')
        (fake_state / "workspace").mkdir()
        (fake_state / "agents").mkdir()

        output_file = tmp_path / "instance.yaml"

        with patch("clawteam_glm.detector.detect_openclaw_version", return_value="2026.5.4"):
            with patch("clawteam_glm.detector.detect_state_dir", return_value=fake_state):
                detect_instance(output_path=output_file)

        assert output_file.exists()
        data = yaml.safe_load(output_file.read_text())
        assert data["openclaw"]["version"] == "2026.5.4"

    def test_raises_when_openclaw_not_found(self):
        with patch("clawteam_glm.detector.detect_state_dir", return_value=None):
            with pytest.raises(RuntimeError, match="OpenClaw"):
                detect_instance()
