# src/clawteam_glm/memory.py
"""Agent memory export and import by role_key."""

import shutil
import tarfile
from pathlib import Path

MEMORY_FILES = {"MEMORY.md", "USER.md"}
MEMORY_DIR_MAP = {"memory": "daily", "daily": "daily"}


def export_memory(workspace: Path, backup_dir: Path | None = None, archive_path: Path | None = None) -> None:
    if backup_dir is not None:
        _export_to_dir(workspace, backup_dir)
    if archive_path is not None:
        _export_to_archive(workspace, archive_path)


def _export_to_dir(workspace: Path, backup_dir: Path) -> None:
    backup_dir.mkdir(parents=True, exist_ok=True)
    for filename in MEMORY_FILES:
        src = workspace / filename
        if src.exists():
            shutil.copy2(str(src), str(backup_dir / filename))
    for src_name, dst_name in MEMORY_DIR_MAP.items():
        src_dir = workspace / src_name
        if src_dir.exists() and src_dir.is_dir():
            dst_dir = backup_dir / dst_name
            if dst_dir.exists():
                shutil.rmtree(str(dst_dir))
            shutil.copytree(str(src_dir), str(dst_dir))


def _export_to_archive(workspace: Path, archive_path: Path) -> None:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w:gz") as tar:
        for filename in MEMORY_FILES:
            src = workspace / filename
            if src.exists():
                tar.add(str(src), arcname=filename)
        for src_name, dst_name in MEMORY_DIR_MAP.items():
            src_dir = workspace / src_name
            if src_dir.exists() and src_dir.is_dir():
                tar.add(str(src_dir), arcname=dst_name)


def import_memory(source: Path, workspace: Path, force: bool = False) -> None:
    workspace.mkdir(parents=True, exist_ok=True)
    if source.is_file() and tarfile.is_tarfile(str(source)):
        _import_from_archive(source, workspace, force)
    else:
        _import_from_dir(source, workspace, force)


def _import_from_dir(source: Path, workspace: Path, force: bool) -> None:
    for filename in MEMORY_FILES:
        src = source / filename
        dst = workspace / filename
        if src.exists():
            if dst.exists() and not force:
                raise FileExistsError(f"{filename} already exists in workspace. Use force=True to overwrite.")
            shutil.copy2(str(src), str(dst))
    for src_name, dst_name in MEMORY_DIR_MAP.items():
        src_dir = source / src_name
        dst_dir = workspace / dst_name
        if src_dir.exists() and src_dir.is_dir():
            if dst_dir.exists() and not force:
                raise FileExistsError(f"{dst_name}/ already exists in workspace. Use force=True to overwrite.")
            if dst_dir.exists():
                shutil.rmtree(str(dst_dir))
            shutil.copytree(str(src_dir), str(dst_dir))


def _import_from_archive(archive_path: Path, workspace: Path, force: bool) -> None:
    with tarfile.open(archive_path, "r:gz") as tar:
        for member in tar.getmembers():
            target = workspace / member.name
            if target.exists() and not force:
                raise FileExistsError(f"{member.name} already exists. Use force=True to overwrite.")
        tar.extractall(path=str(workspace))
