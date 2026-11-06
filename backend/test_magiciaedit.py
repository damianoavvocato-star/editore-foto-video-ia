"""MagicIAedit provider and API contract tests."""
import time

from fastapi.testclient import TestClient

from backend import magiciaedit, server


def test_provider_is_disabled_without_server_credentials(monkeypatch):
    for key in ("MAGICIA_API_KEY", "MAGICIA_MODEL", "MAGICIA_API_BASE_URL"):
        monkeypatch.delenv(key, raising=False)
    assert magiciaedit.provider_configured() is False


def test_provider_requires_https(monkeypatch, tmp_path):
    monkeypatch.setenv("MAGICIA_API_KEY", "test-key")
    monkeypatch.setenv("MAGICIA_MODEL", "vision-model")
    monkeypatch.setenv("MAGICIA_API_BASE_URL", "http://provider.example/v1")
    try:
        magiciaedit.create_magic_plan({"a" * 32: tmp_path / "photo.jpg"})
    except magiciaedit.MagicIAError as exc:
        assert "HTTPS" in str(exc)
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
