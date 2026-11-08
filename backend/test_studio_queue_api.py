"""Authenticated API tests for the reviewed Studio queue boundary."""
from fastapi.testclient import TestClient

from backend.accounts import AccountStore
from backend.server import app
from backend.studio import StudioJobStore
from backend.studio_queue import StudioJobQueue
import backend.server as server


def test_reviewed_draft_can_be_enqueued_idempotently_and_polled_per_account(tmp_path, monkeypatch):
    accounts = AccountStore(tmp_path / "accounts.sqlite3")
    owner = accounts.register("studio_queue_owner", "studio queue owner password")
    other = accounts.register("studio_queue_other", "studio queue other password")
    owner_token, _ = accounts.issue_session(owner["userId"])
    other_token, _ = accounts.issue_session(other["userId"])
    monkeypatch.setattr(server, "_account_store", lambda: accounts)
    monkeypatch.setattr(server, "_studio_store", lambda: StudioJobStore(tmp_path / "drafts.sqlite3"))
    monkeypatch.setattr(server, "_studio_queue", lambda: StudioJobQueue(tmp_path / "queue.sqlite3"))
    client = TestClient(app)
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    other_headers = {"Authorization": f"Bearer {other_token}"}

    draft = client.post(
        "/v1/studio/jobs",
        headers=owner_headers,
        json={"task": "script_to_video", "script": "A reviewed test script"},
    )
    assert draft.status_code == 200
    draft_id = draft.json()["jobId"]

    first = client.post(f"/v1/studio/jobs/{draft_id}/enqueue", headers=owner_headers)
    assert first.status_code == 200
    queued_id = first.json()["jobId"]
    assert first.json()["state"] == "queued"
    assert first.json()["created"] is True
    assert first.json()["providerSubmissionEnabled"] is False

    replay = client.post(f"/v1/studio/jobs/{draft_id}/enqueue", headers=owner_headers)
    assert replay.status_code == 200
    assert replay.json()["jobId"] == queued_id
    assert replay.json()["created"] is False

    own_status = client.get(f"/v1/studio/queue/{queued_id}", headers=owner_headers)
    assert own_status.status_code == 200
    assert own_status.json()["state"] == "queued"
    assert own_status.json()["request"]["script"] == "A reviewed test script"
    assert client.get(f"/v1/studio/queue/{queued_id}", headers=other_headers).status_code == 404
    assert client.get("/v1/studio/queue", headers=owner_headers).json()["jobs"][0]["jobId"] == queued_id


def test_studio_queue_requires_authenticated_account(tmp_path, monkeypatch):
    monkeypatch.setattr(server, "_studio_store", lambda: StudioJobStore(tmp_path / "drafts.sqlite3"))
    monkeypatch.setattr(server, "_studio_queue", lambda: StudioJobQueue(tmp_path / "queue.sqlite3"))
    client = TestClient(app)
    assert client.get("/v1/studio/queue").status_code == 401
    assert client.post("/v1/studio/jobs/not-a-valid-id/enqueue").status_code == 401


def test_enqueue_rejects_unknown_or_foreign_draft_without_leaking_it(tmp_path, monkeypatch):
    accounts = AccountStore(tmp_path / "accounts.sqlite3")
    owner = accounts.register("studio_queue_owner2", "studio queue owner password")
    other = accounts.register("studio_queue_other2", "studio queue other password")
    owner_token, _ = accounts.issue_session(owner["userId"])
    other_token, _ = accounts.issue_session(other["userId"])
    monkeypatch.setattr(server, "_account_store", lambda: accounts)
    monkeypatch.setattr(server, "_studio_store", lambda: StudioJobStore(tmp_path / "drafts.sqlite3"))
    monkeypatch.setattr(server, "_studio_queue", lambda: StudioJobQueue(tmp_path / "queue.sqlite3"))
    client = TestClient(app)
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    other_headers = {"Authorization": f"Bearer {other_token}"}
    draft = client.post(
        "/v1/studio/jobs", headers=owner_headers,
        json={"task": "script_to_video", "script": "private script"},
    )
    draft_id = draft.json()["jobId"]
    assert client.post(
        f"/v1/studio/jobs/{draft_id}/enqueue", headers=other_headers
    ).status_code == 404
    assert client.post(
        f"/v1/studio/jobs/{'a' * 32}/enqueue", headers=owner_headers
    ).status_code == 404
