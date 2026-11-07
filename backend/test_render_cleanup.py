"""Regression tests for cleanup of partial render outputs."""
import subprocess
import threading
import uuid

import pytest
from fastapi import HTTPException

from backend import server


def test_failed_final_render_removes_partial_output(tmp_path, monkeypatch):
    root = tmp_path
    assets = root / "assets"
    outputs = root / "outputs"
    assets.mkdir()
    outputs.mkdir()
    asset_id = uuid.uuid4().hex
    job_id = uuid.uuid4().hex
    (assets / f"{asset_id}.png").write_bytes(b"test-image")

    monkeypatch.setattr(server, "ROOT", root)
    monkeypatch.setattr(server, "ASSETS", assets)
    monkeypatch.setattr(server, "OUTPUTS", outputs)
    monkeypatch.setattr(server.shutil, "which", lambda _binary: "/usr/bin/ffmpeg")

    calls = 0

    def fake_run(command, **kwargs):
        nonlocal calls
        calls += 1
        target = command[-1]
        if calls == 1:
            # Simulate a successfully generated intermediate clip.
            open(target, "wb").write(b"segment")
            return subprocess.CompletedProcess(command, 0, "", "")
        # Simulate FFmpeg creating a truncated final file before failing.
        open(target, "wb").write(b"partial-output")
        return subprocess.CompletedProcess(command, 1, "", "simulated encoder failure")

    monkeypatch.setattr(server.subprocess, "run", fake_run)
    server.jobs[job_id] = {"state": "queued", "progress": 0.0, "message": "Queued"}
    server.cancel_events[job_id] = threading.Event()

    try:
        server._render_job(
            job_id,
            {
                "width": 160,
                "height": 120,
                "tracks": [
                    {
                        "kind": "video",
                        "clips": [
                            {
                                "kind": "image",
                                "assetId": asset_id,
                                "durationMs": 1000,
                            }
                        ],
                    }
                ],
            },
            {"resolution": "p720", "fps": 24, "container": "mp4"},
        )

        assert server.jobs[job_id]["state"] == "failed"
        assert list(outputs.iterdir()) == []
    finally:
        server.jobs.pop(job_id, None)
        server.cancel_events.pop(job_id, None)


def test_render_rejects_non_uuid_asset_ids_before_creating_job():
    with pytest.raises(HTTPException) as error:
        server.create_render(
            server.RenderBody(
                project={
                    "tracks": [
                        {
                            "kind": "video",
                            "clips": [
                                {"kind": "video", "assetId": "not-a-generated-asset-id"}
                            ],
                        }
                    ]
                }
            )
        )

    assert error.value.status_code == 422
    assert error.value.detail == "Identificativo media non valido"
