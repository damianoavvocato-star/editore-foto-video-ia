"""Conservative cleanup for abandoned media-processing temporary files."""
from __future__ import annotations

import shutil
import stat
import time
from pathlib import Path
from typing import Iterable


def cleanup_stale_media(
    assets_dir: str | Path,
    work_dir: str | Path,
    *,
    active_job_ids: Iterable[str] = (),
    older_than_seconds: int = 24 * 60 * 60,
    now: float | None = None,
) -> dict[str, int]:
    """Remove only old partial uploads and inactive per-job work directories.

    Uploaded source assets and rendered outputs are deliberately never touched.
    Symlinks and paths outside the two designated directories are ignored.
    """
    if not isinstance(older_than_seconds, int) or older_than_seconds < 1:
        raise ValueError("older_than_seconds must be a positive integer")
    timestamp = time.time() if now is None else now
    cutoff = timestamp - older_than_seconds
    active = set(active_job_ids)
    removed_files = 0
    removed_directories = 0

    assets = Path(assets_dir)
    if assets.exists() and not assets.is_symlink():
        root = assets.resolve()
        for candidate in assets.iterdir():
            try:
                metadata = candidate.lstat()
                if not stat.S_ISREG(metadata.st_mode):
                    continue
                if not candidate.name.endswith(".part") or metadata.st_mtime >= cutoff:
                    continue
                if candidate.resolve().parent != root:
                    continue
                candidate.unlink()
                removed_files += 1
            except (FileNotFoundError, OSError):
                continue

    work = Path(work_dir)
    if work.exists() and not work.is_symlink():
        root = work.resolve()
        for candidate in work.iterdir():
            try:
                metadata = candidate.lstat()
                if not stat.S_ISDIR(metadata.st_mode):
                    continue
                if candidate.name in active or metadata.st_mtime >= cutoff:
                    continue
                if candidate.resolve().parent != root:
                    continue
                shutil.rmtree(candidate)
                removed_directories += 1
            except (FileNotFoundError, OSError):
                continue

    return {
        "removed_files": removed_files,
        "removed_directories": removed_directories,
    }
