import os
import time

import pytest

from backend.media_cleanup import cleanup_stale_media


def test_cleanup_removes_only_old_partial_uploads_and_orphan_work(tmp_path):
    assets = tmp_path / "assets"
    work = tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    old_partial = assets / ".upload.mp4.part"
    old_partial.write_bytes(b"partial")
    source_asset = assets / ("a" * 32 + ".jpg")
    source_asset.write_bytes(b"keep")
    output_dir = tmp_path / "outputs"
    output_dir.mkdir()
    rendered_output = output_dir / ("b" * 32 + ".mp4")
    rendered_output.write_bytes(b"keep")
    orphan = work / ("c" * 32)
    orphan.mkdir()
    (orphan / "frame.jpg").write_bytes(b"temporary")
    recent = work / ("d" * 32)
    recent.mkdir()
    active = work / ("e" * 32)
    active.mkdir()

    old = time.time() - 48 * 60 * 60
    os.utime(old_partial, (old, old))
    os.utime(orphan, (old, old))
    os.utime(active, (old, old))

    result = cleanup_stale_media(
        assets, work, active_job_ids={active.name},
        older_than_seconds=24 * 60 * 60,
    )

    assert result == {"removed_files": 1, "removed_directories": 1}
    assert not old_partial.exists()
    assert not orphan.exists()
    assert source_asset.read_bytes() == b"keep"
    assert rendered_output.read_bytes() == b"keep"
    assert recent.exists()
    assert active.exists()


def test_cleanup_ignores_symlinks_and_never_follows_them(tmp_path):
    assets = tmp_path / "assets"
    work = tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    protected = outside / "protected.part"
    protected.write_bytes(b"keep")
    link = assets / "linked.part"
    try:
        link.symlink_to(protected)
    except (OSError, NotImplementedError):
        return

    result = cleanup_stale_media(
        assets, work, older_than_seconds=1, now=time.time() + 10,
    )

    assert result["removed_files"] == 0
    assert protected.read_bytes() == b"keep"
    assert link.is_symlink()


def test_cleanup_rejects_non_positive_retention(tmp_path):
    with pytest.raises(ValueError):
        cleanup_stale_media(tmp_path / "assets", tmp_path / "work", older_than_seconds=0)
