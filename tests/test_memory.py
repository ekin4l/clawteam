# tests/test_memory.py
import tarfile
from pathlib import Path

import pytest
from clawteam_glm.memory import export_memory, import_memory


class TestExportMemory:
    def test_exports_memory_files(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("long term memory")
        (workspace / "USER.md").write_text("user info")
        (workspace / "memory").mkdir()
        (workspace / "memory" / "2026-05-05.md").write_text("daily log")
        (workspace / "SOUL.md").write_text("soul")
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        export_memory(workspace, backup_dir / "assistant")
        assert (backup_dir / "assistant" / "MEMORY.md").read_text() == "long term memory"
        assert (backup_dir / "assistant" / "USER.md").read_text() == "user info"
        assert (backup_dir / "assistant" / "daily" / "2026-05-05.md").read_text() == "daily log"
        assert not (backup_dir / "assistant" / "SOUL.md").exists()

    def test_creates_tar_archive(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("memory")
        (workspace / "memory").mkdir()
        (workspace / "memory" / "log.md").write_text("log")
        archive_path = tmp_path / "backup.tar.gz"
        export_memory(workspace, archive_path=archive_path)
        assert archive_path.exists()
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()
            assert any("MEMORY.md" in n for n in names)

    def test_handles_empty_workspace(self, tmp_path):
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        export_memory(workspace, backup_dir / "assistant")
        assert (backup_dir / "assistant").exists()


class TestImportMemory:
    def test_imports_memory_to_workspace(self, tmp_path):
        source = tmp_path / "source"
        source.mkdir()
        (source / "MEMORY.md").write_text("imported memory")
        (source / "USER.md").write_text("imported user")
        (source / "daily").mkdir()
        (source / "daily" / "log.md").write_text("daily log")
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        import_memory(source, workspace)
        assert (workspace / "MEMORY.md").read_text() == "imported memory"
        assert (workspace / "USER.md").read_text() == "imported user"
        assert (workspace / "daily" / "log.md").read_text() == "daily log"

    def test_imports_from_tar_archive(self, tmp_path):
        source = tmp_path / "source"
        source.mkdir()
        (source / "MEMORY.md").write_text("tar memory")
        archive = tmp_path / "backup.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(str(source / "MEMORY.md"), arcname="MEMORY.md")
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        import_memory(archive, workspace)
        assert (workspace / "MEMORY.md").exists()

    def test_skips_if_target_has_memory(self, tmp_path):
        source = tmp_path / "source"
        source.mkdir()
        (source / "MEMORY.md").write_text("new memory")
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("existing memory")
        with pytest.raises(FileExistsError, match="MEMORY.md"):
            import_memory(source, workspace)

    def test_force_overwrites_existing(self, tmp_path):
        source = tmp_path / "source"
        source.mkdir()
        (source / "MEMORY.md").write_text("new memory")
        workspace = tmp_path / "workspace"
        workspace.mkdir()
        (workspace / "MEMORY.md").write_text("existing memory")
        import_memory(source, workspace, force=True)
        assert (workspace / "MEMORY.md").read_text() == "new memory"
