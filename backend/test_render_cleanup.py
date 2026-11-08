"""Regression tests for cleanup of partial render outputs."""
import subprocess
import threading
import uuid
from types import SimpleNamespace

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

    monkeypatch.setattr(
        server, "_run_ffmpeg",
        lambda _job_id, command, timeout: fake_run(
            command, capture_output=True, text=True, timeout=timeout
        ),
    )
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
    request = SimpleNamespace(state=SimpleNamespace(account=None, local_dev=True))
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
            ),
            request,
            idempotency_key=None,
        )

    assert error.value.status_code == 422
    assert error.value.detail == "Identificativo media non valido"


def test_cancellation_wins_if_requested_before_render_finalization(tmp_path, monkeypatch):
    assets = tmp_path / "assets"
    outputs = tmp_path / "outputs"
    assets.mkdir()
    outputs.mkdir()
    asset_id = uuid.uuid4().hex
    job_id = uuid.uuid4().hex
    (assets / f"{asset_id}.png").write_bytes(b"test-image")

    monkeypatch.setattr(server, "ROOT", tmp_path)
    monkeypatch.setattr(server, "ASSETS", assets)
    monkeypatch.setattr(server, "OUTPUTS", outputs)
    monkeypatch.setattr(server.shutil, "which", lambda _binary: "/usr/bin/ffmpeg")

    def fake_run(command, **kwargs):
        with open(command[-1], "wb") as generated:
            generated.write(b"completed-render")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(
        server, "_run_ffmpeg",
        lambda _job_id, command, timeout: fake_run(
            command, capture_output=True, text=True, timeout=timeout
        ),
    )
    cancel_event = threading.Event()
    server.jobs[job_id] = {"state": "queued", "progress": 0.0, "message": "Queued"}
    server.cancel_events[job_id] = cancel_event

    real_chmod = server.os.chmod

    def cancel_during_output_permission_update(path, mode):
        if Path(path).parent == outputs:
            cancel_event.set()
        return real_chmod(path, mode)

    from pathlib import Path
    monkeypatch.setattr(server.os, "chmod", cancel_during_output_permission_update)

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

        assert server.jobs[job_id]["state"] == "cancelled"
        assert list(outputs.iterdir()) == []
    finally:
        server.jobs.pop(job_id, None)
        server.cancel_events.pop(job_id, None)


def test_cancel_stops_active_ffmpeg_process(tmp_path, monkeypatch):
    started = threading.Event()
    terminated = threading.Event()
    cancel_event = threading.Event()

    class FakeProcess:
        returncode = -15

        def communicate(self, timeout=None):
            started.set()
            assert terminated.wait(timeout=2)
            return "", "terminated"

        def terminate(self):
            terminated.set()

        def kill(self):
            terminated.set()

    job_id = uuid.uuid4().hex
    server.cancel_events[job_id] = cancel_event
    monkeypatch.setattr(server.subprocess, "Popen", lambda *args, **kwargs: FakeProcess())
    outcome = []

    def run_render_command():
        try:
            server._run_ffmpeg(job_id, ["ffmpeg", "-version"], timeout=5)
        except server.RenderCancelled:
            outcome.append("cancelled")

    worker = threading.Thread(target=run_render_command)
    worker.start()
    assert started.wait(timeout=2)
    with server.lock:
        cancel_event.set()
        server._stop_render_process(job_id)
    worker.join(timeout=2)

    try:
        assert not worker.is_alive()
        assert terminated.is_set()
        assert outcome == ["cancelled"]
        assert job_id not in server.active_render_processes
    finally:
        server.cancel_events.pop(job_id, None)
