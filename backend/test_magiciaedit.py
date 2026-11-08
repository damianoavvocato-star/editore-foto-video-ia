"""MagicIAedit provider and API contract tests."""
import threading
import time

from fastapi.testclient import TestClient

from backend import magiciaedit, server


def test_provider_is_disabled_without_server_credentials(monkeypatch):
    for key in ("MAGICIA_API_KEY", "MAGICIA_MODEL", "MAGICIA_API_BASE_URL"):
        monkeypatch.delenv(key, raising=False)
    assert magiciaedit.provider_configured() is False


def test_provider_redirects_are_rejected_to_protect_authorization_header():
    handler = magiciaedit._NoRedirect()
    assert handler.redirect_request(
        None, None, 302, "Found", {}, "https://attacker.example/collect"
    ) is None


def test_provider_requires_https(monkeypatch, tmp_path):
    monkeypatch.setenv("MAGICIA_API_KEY", "test-key")
    monkeypatch.setenv("MAGICIA_MODEL", "vision-model")
    monkeypatch.setenv("MAGICIA_API_BASE_URL", "http://provider.example/v1")
    try:
        magiciaedit.create_magic_plan({"a" * 32: tmp_path / "photo.jpg"})
    except magiciaedit.MagicIAError as exc:
        assert "non configurato" in str(exc)
    else:
        raise AssertionError("HTTP provider URL must be rejected")


def test_plan_rejects_unknown_asset_ids():
    try:
        magiciaedit._normalise_plan(
            {"clips": [{"assetId": "b" * 32}]},
            {"a" * 32},
        )
    except magiciaedit.MagicIAError as exc:
        assert "media non selezionato" in str(exc)
    else:
        raise AssertionError("Unknown asset must be rejected")


def test_plan_clamps_values_and_builds_timeline():
    asset_id = "a" * 32
    plan = magiciaedit._normalise_plan(
        {"title": "Prova", "clips": [
            {"assetId": asset_id, "sourceStartMs": -20, "durationMs": 99999,
             "transitionAfterMs": 9999, "transitionAfter": "invalid"}
        ]},
        {asset_id},
    )
    clip = plan["clips"][0]
    assert clip["sourceStartMs"] == 0
    assert clip["durationMs"] == 20000
    assert clip["transitionAfterMs"] == 2000
    assert clip["transitionAfter"] == "fade"
    assert plan["durationMs"] == 18000


def test_ai_endpoint_reports_missing_cloud_configuration(monkeypatch):
    monkeypatch.setattr(server, "provider_configured", lambda: False)
    response = TestClient(server.app).post(
        "/v1/ai/jobs",
        json={"task": "magicIAedit", "assetIds": ["a" * 32]},
    )
    assert response.status_code == 503


def test_ai_endpoint_rejects_duplicate_asset_ids(monkeypatch):
    monkeypatch.setattr(server, "provider_configured", lambda: True)
    asset_id = "a" * 32
    response = TestClient(server.app).post(
        "/v1/ai/jobs",
        json={"task": "magicIAedit", "assetIds": [asset_id, asset_id]},
    )
    assert response.status_code == 422


def test_ai_endpoint_rejects_more_than_twenty_assets(monkeypatch):
    monkeypatch.setattr(server, "provider_configured", lambda: True)
    response = TestClient(server.app).post(
        "/v1/ai/jobs",
        json={"task": "magicIAedit", "assetIds": [f"{index:032x}" for index in range(21)]},
    )
    assert response.status_code == 422


def test_ai_job_returns_validated_plan(monkeypatch, tmp_path):
    asset_id = "a" * 32
    monkeypatch.setattr(server, "provider_configured", lambda: True)
    monkeypatch.setattr(server, "ASSETS", tmp_path)
    (tmp_path / f"{asset_id}.jpg").write_bytes(b"placeholder")

    def fake_plan(paths, options, cancel_event):
        assert list(paths) == [asset_id]
        assert options["goal"] == "travel montage"
        return {"title": "Viaggio", "clips": []}

    monkeypatch.setattr(server, "create_magic_plan", fake_plan)
    client = TestClient(server.app)
    response = client.post(
        "/v1/ai/jobs",
        json={"task": "magicIAedit", "assetIds": [asset_id],
              "options": {"goal": "travel montage"}},
    )
    assert response.status_code == 200
    job_id = response.json()["jobId"]
    for _ in range(50):
        status = client.get(f"/v1/jobs/{job_id}").json()
        if status["state"] in {"succeeded", "failed", "cancelled"}:
            break
        time.sleep(0.01)
    assert status["state"] == "succeeded"
    assert status["result"]["title"] == "Viaggio"


def test_magic_plan_rejects_single_oversized_asset(monkeypatch, tmp_path):
    monkeypatch.setenv("MAGICIA_API_KEY", "test-key")
    monkeypatch.setenv("MAGICIA_MODEL", "vision-model")
    monkeypatch.setenv("MAGICIA_API_BASE_URL", "https://provider.example/v1")
    asset = tmp_path / "large.mp4"
    with asset.open("wb") as stream:
        stream.truncate(magiciaedit.MAX_ASSET_BYTES + 1)
    try:
        magiciaedit.create_magic_plan({"a" * 32: asset})
    except magiciaedit.MagicIAError as exc:
        assert "inferiore a 100 MB" in str(exc)
    else:
        raise AssertionError("Oversized media must be rejected")


def test_magic_plan_rejects_oversized_combined_selection(monkeypatch, tmp_path):
    monkeypatch.setenv("MAGICIA_API_KEY", "test-key")
    monkeypatch.setenv("MAGICIA_MODEL", "vision-model")
    monkeypatch.setenv("MAGICIA_API_BASE_URL", "https://provider.example/v1")
    assets = {}
    for index in range(5):
        asset = tmp_path / f"media-{index}.mp4"
        with asset.open("wb") as stream:
            stream.truncate(90 * 1024 * 1024)
        assets[str(index) * 32] = asset
    try:
        magiciaedit.create_magic_plan(assets)
    except magiciaedit.MagicIAError as exc:
        assert "400 MB" in str(exc)
    else:
        raise AssertionError("Oversized combined selection must be rejected")



def test_magic_plan_rejects_image_over_twenty_megabytes(monkeypatch, tmp_path):
    monkeypatch.setenv("MAGICIA_API_KEY", "test-key")
    monkeypatch.setenv("MAGICIA_MODEL", "vision-model")
    monkeypatch.setenv("MAGICIA_API_BASE_URL", "https://provider.example/v1")
    asset = tmp_path / "large.jpg"
    with asset.open("wb") as stream:
        stream.truncate(magiciaedit.MAX_IMAGE_ASSET_BYTES + 1)
    try:
        magiciaedit.create_magic_plan({"a" * 32: asset})
    except magiciaedit.MagicIAError as exc:
        assert "20 MB" in str(exc)
    else:
        raise AssertionError("Oversized image must be rejected")


def test_magic_plan_rejects_more_than_twenty_media(monkeypatch, tmp_path):
    monkeypatch.setenv("MAGICIA_API_KEY", "test-key")
    monkeypatch.setenv("MAGICIA_MODEL", "vision-model")
    monkeypatch.setenv("MAGICIA_API_BASE_URL", "https://provider.example/v1")
    assets = {f"{index:032x}": tmp_path / f"{index}.mp4" for index in range(21)}
    try:
        magiciaedit.create_magic_plan(assets)
    except magiciaedit.MagicIAError as exc:
        assert "1 a 20" in str(exc)
    else:
        raise AssertionError("More than twenty media must be rejected")


def test_magic_media_preprocessing_stops_immediately_when_cancelled(tmp_path):
    cancelled = threading.Event()
    cancelled.set()
    missing_asset = tmp_path / "not-created.jpg"
    try:
        magiciaedit._media_parts({"a" * 32: missing_asset}, cancelled)
    except magiciaedit.MagicIAError as exc:
        assert "annullata" in str(exc)
    else:
        raise AssertionError("Cancelled preprocessing must stop before reading media")


def test_video_frame_extraction_checks_cancellation_before_ffprobe(monkeypatch, tmp_path):
    cancelled = threading.Event()
    cancelled.set()

    def unexpected_subprocess(*args, **kwargs):
        raise AssertionError("ffprobe must not start after cancellation")

    monkeypatch.setattr(magiciaedit.subprocess, "run", unexpected_subprocess)
    try:
        magiciaedit._video_frames(tmp_path / "clip.mp4", cancelled)
    except magiciaedit.MagicIAError as exc:
        assert "annullata" in str(exc)
    else:
        raise AssertionError("Cancelled frame extraction must stop immediately")


def test_ai_job_can_be_cancelled_before_provider_finishes(monkeypatch, tmp_path):
    asset_id = "c" * 32
    monkeypatch.setattr(server, "provider_configured", lambda: True)
    monkeypatch.setattr(server, "ASSETS", tmp_path)
    (tmp_path / f"{asset_id}.jpg").write_bytes(b"placeholder")
    provider_started = threading.Event()

    def slow_plan(paths, options, cancel_event):
        provider_started.set()
        assert cancel_event.wait(timeout=2), "Cancellation was not propagated to provider"
        raise magiciaedit.MagicIAError("Elaborazione annullata.")

    monkeypatch.setattr(server, "create_magic_plan", slow_plan)
    client = TestClient(server.app)
    response = client.post(
        "/v1/ai/jobs", json={"task": "magicIAedit", "assetIds": [asset_id]},
    )
    assert response.status_code == 200
    job_id = response.json()["jobId"]
    assert provider_started.wait(timeout=2)

    cancelled = client.delete(f"/v1/jobs/{job_id}")
    assert cancelled.status_code == 200
    assert cancelled.json()["ok"] is True
    for _ in range(100):
        status = client.get(f"/v1/jobs/{job_id}").json()
        if status["state"] in {"succeeded", "failed", "cancelled"}:
            break
        time.sleep(0.01)
    assert status["state"] == "cancelled"


def test_plan_rejects_non_numeric_timeline_values_cleanly():
    asset_id = "d" * 32
    for invalid_value in (None, "not-a-number", float("inf")):
        try:
            magiciaedit._normalise_plan(
                {"clips": [{"assetId": asset_id, "durationMs": invalid_value}]},
                {asset_id},
            )
        except magiciaedit.MagicIAError as exc:
            assert "tempi non validi" in str(exc)
        else:
            raise AssertionError("Malformed timeline values must be rejected")


def test_magic_ai_cannot_analyse_another_users_media(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.register("media_owner", "media owner password long")
    stranger = store.register("media_stranger", "media stranger password long")
    _, owner_token, _ = store.login("media_owner", "media owner password long")
    _, stranger_token, _ = store.login("media_stranger", "media stranger password long")
    asset_id = "e" * 32
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setattr(server, "provider_configured", lambda: True)
    monkeypatch.setattr(server, "ASSETS", tmp_path / "assets")
    server.ASSETS.mkdir()
    (server.ASSETS / f"{asset_id}.jpg").write_bytes(b"test image")
    store.claim_media_resource("asset", asset_id, owner["userId"])
    client = TestClient(server.app)
    response = client.post(
        "/v1/ai/jobs",
        headers={"Authorization": f"Bearer {stranger_token}"},
        json={"task": "magicIAedit", "assetIds": [asset_id]},
    )
    assert response.status_code == 404


def test_magic_ai_jobs_are_private_to_their_account(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.register("job_owner", "job owner password long")
    stranger = store.register("job_stranger", "job stranger password long")
    _, owner_token, _ = store.login("job_owner", "job owner password long")
    _, stranger_token, _ = store.login("job_stranger", "job stranger password long")
    job_id = "f" * 32
    monkeypatch.setattr(server, "_account_store", lambda: store)
    store.claim_media_resource("job", job_id, owner["userId"])
    with server.lock:
        server.jobs[job_id] = {"state": "rendering", "progress": 0.2, "message": "Analisi"}
        server.cancel_events[job_id] = threading.Event()
    client = TestClient(server.app)
    stranger_headers = {"Authorization": f"Bearer {stranger_token}"}
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    try:
        assert client.get(f"/v1/jobs/{job_id}", headers=stranger_headers).status_code == 404
        assert client.delete(f"/v1/jobs/{job_id}", headers=stranger_headers).status_code == 404
        own_status = client.get(f"/v1/jobs/{job_id}", headers=owner_headers)
        assert own_status.status_code == 200
        assert client.delete(f"/v1/jobs/{job_id}", headers=owner_headers).status_code == 200
        assert server.jobs[job_id]["state"] == "cancelled"
    finally:
        with server.lock:
            server.jobs.pop(job_id, None)
            server.cancel_events.pop(job_id, None)
