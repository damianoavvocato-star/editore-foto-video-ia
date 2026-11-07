"""API-level regression tests for per-account media isolation."""
import io
import threading

from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore


def _session(tmp_path, monkeypatch, username):
    monkeypatch.setenv("MEDIA_AUTH_DB", str(tmp_path / "accounts.sqlite3"))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    monkeypatch.setattr(server, "TOKEN", "legacy-shared-secret")
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register(username, "a sufficiently long test password")
    token, _ = store.issue_session(account["userId"])
    return store, account, {"Authorization": f"Bearer {token}"}


def test_upload_is_owned_and_cannot_be_used_by_another_account(tmp_path, monkeypatch):
    assets = tmp_path / "assets"
    assets.mkdir()
    monkeypatch.setattr(server, "ASSETS", assets)
    store, alice, alice_headers = _session(tmp_path, monkeypatch, "alice_user")
    _, bob, bob_headers = _session(tmp_path, monkeypatch, "bob_user")
    client = TestClient(server.app)

    uploaded = client.post(
        "/v1/assets",
        headers=alice_headers,
        files={"file": ("photo.png", io.BytesIO(b"image-bytes"), "image/png")},
    )
    assert uploaded.status_code == 200
    asset_id = uploaded.json()["assetId"]
    assert store.owns_media_resource("asset", asset_id, alice["userId"])
    assert not store.owns_media_resource("asset", asset_id, bob["userId"])

    response = client.post(
        "/v1/render/jobs",
        headers=bob_headers,
        json={"project": {"tracks": [{"kind": "video", "clips": [
            {"kind": "image", "assetId": asset_id, "durationMs": 1000}
        ]}]}},
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "Risorsa non trovata."


def test_job_status_cancel_and_output_are_private_to_owner(tmp_path, monkeypatch):
    store, alice, alice_headers = _session(tmp_path, monkeypatch, "alice_user")
    _, bob, bob_headers = _session(tmp_path, monkeypatch, "bob_user")
    job_id = "a" * 32
    store.claim_media_resource("job", job_id, alice["userId"])
    server.jobs[job_id] = {"state": "completed", "progress": 1.0, "message": "Done"}
    server.cancel_events[job_id] = threading.Event()
    outputs = tmp_path / "outputs"
    outputs.mkdir()
    monkeypatch.setattr(server, "OUTPUTS", outputs)
    (outputs / f"{job_id}.mp4").write_bytes(b"private-output")
    client = TestClient(server.app)

    assert client.get(f"/v1/jobs/{job_id}", headers=alice_headers).status_code == 200
    assert client.get(f"/v1/jobs/{job_id}", headers=bob_headers).status_code == 404
    assert client.delete(f"/v1/jobs/{job_id}", headers=bob_headers).status_code == 404
    assert client.get(f"/v1/outputs/{job_id}", headers=bob_headers).status_code == 404
    assert client.get(f"/v1/outputs/{job_id}", headers=alice_headers).content == b"private-output"

    server.jobs.pop(job_id, None)
    server.cancel_events.pop(job_id, None)


def test_legacy_shared_token_is_rejected_even_when_configured(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDIA_AUTH_DB", str(tmp_path / "accounts.sqlite3"))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    monkeypatch.setattr(server, "TOKEN", "legacy-shared-secret")
    client = TestClient(server.app)
    response = client.get(
        "/v1/jobs/" + "b" * 32,
        headers={"Authorization": "Bearer legacy-shared-secret"},
    )
    assert response.status_code == 401
