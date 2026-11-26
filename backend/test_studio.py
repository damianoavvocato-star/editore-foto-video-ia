"""Tests for Synthesia Studio request validation and private draft storage."""
import pytest
from pydantic import ValidationError

from backend.studio import StudioJobRequest, StudioJobStore, StudioRequestError


def test_studio_accepts_twenty_distinct_languages():
    languages = ["it", "en", "fr", "es", "ar", "de", "pt", "nl", "pl", "tr", "ru", "ja", "ko", "zh", "hi", "sv", "da", "fi", "no", "el"]
    request = StudioJobRequest(task="script_to_video", script="Hello", targetLanguages=languages)
    request.validate_policy()
    assert len(request.targetLanguages) == 20


def test_studio_accepts_script_and_numeric_region_language_tags():
    request = StudioJobRequest(
        task='script_to_video', script='Hello',
        sourceLanguage='zh-Hant-TW', targetLanguages=['sr-Latn-RS', 'es-419'],
    )
    request.validate_policy()
    assert request.sourceLanguage == 'zh-Hant-TW'


def test_studio_rejects_duplicate_or_invalid_languages():
    with pytest.raises(ValidationError):
        StudioJobRequest(task="script_to_video", script="Hello", targetLanguages=["it-IT", "it-IT"])
    with pytest.raises(ValidationError):
        StudioJobRequest(task="script_to_video", script="Hello", targetLanguages=["italiano"])


def test_source_language_cannot_be_a_destination():
    request = StudioJobRequest(
        task="script_to_video", script="Hello",
        sourceLanguage="en-US", targetLanguages=["en-US"],
    )
    with pytest.raises(StudioRequestError):
        request.validate_policy()


def test_personal_avatar_requires_explicit_consent():
    request = StudioJobRequest(
        task="avatar_video", script="Welcome",
        avatarMode="personal", avatarConsent=False,
    )
    with pytest.raises(StudioRequestError, match="consenso"):
        request.validate_policy()


def test_voice_clone_requires_explicit_consent():
    request = StudioJobRequest(
        task="script_to_video", script="Welcome",
        voiceMode="clone", voiceConsent=False,
    )
    with pytest.raises(StudioRequestError, match="consenso"):
        request.validate_policy()


def test_document_and_slide_jobs_require_source_files():
    for task in ("document_to_video", "slides_to_video", "translate_dub"):
        request = StudioJobRequest(task=task)
        with pytest.raises(StudioRequestError):
            request.validate_policy()


def test_interactive_video_must_be_explicitly_enabled():
    request = StudioJobRequest(task="interactive_video", script="Question")
    with pytest.raises(StudioRequestError):
        request.validate_policy()


def test_idempotent_draft_replay_and_user_isolation(tmp_path):
    store = StudioJobStore(tmp_path / "studio.sqlite3")
    request = StudioJobRequest(task="script_to_video", script="A short intro")
    first, created = store.create_draft("user-a", request, "request-1")
    replay, replay_created = store.create_draft("user-a", request, "request-1")
    assert created is True
    assert replay_created is False
    assert replay["jobId"] == first["jobId"]
    assert store.get("user-b", first["jobId"]) is None
    assert store.get("user-a", first["jobId"])["state"] == "draft"


def test_idempotency_key_cannot_be_reused_for_different_content(tmp_path):
    store = StudioJobStore(tmp_path / "studio.sqlite3")
    store.create_draft(
        "user-a", StudioJobRequest(task="script_to_video", script="First"), "same-key"
    )
    with pytest.raises(StudioRequestError, match="idempotenza"):
        store.create_draft(
            "user-a", StudioJobRequest(task="script_to_video", script="Second"), "same-key"
        )


def test_only_owner_can_delete_draft(tmp_path):
    store = StudioJobStore(tmp_path / "studio.sqlite3")
    draft, _ = store.create_draft("user-a", StudioJobRequest(task="script_to_video", script="Hello"))
    assert store.delete_draft("user-b", draft["jobId"]) is False
    assert store.delete_draft("user-a", draft["jobId"]) is True


def test_persisted_drafts_survive_store_recreation(tmp_path):
    path = tmp_path / "studio.sqlite3"
    store = StudioJobStore(path)
    draft, _ = store.create_draft("user-a", StudioJobRequest(task="script_to_video", script="Hello"))
    reopened = StudioJobStore(path)
    assert reopened.get("user-a", draft["jobId"])["request"]["script"] == "Hello"


def _studio_api_user(store, username):
    account = store.register(username, "a sufficiently long password")
    token, _ = store.issue_session(account["userId"])
    return account, {"Authorization": f"Bearer {token}"}


def test_studio_api_creates_and_lists_private_drafts(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from backend import server
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    user, headers = _studio_api_user(store, "studio_user")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setenv("MEDIA_STUDIO_DB", str(tmp_path / "studio.sqlite3"))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    client = TestClient(server.app)

    created = client.post(
        "/v1/studio/jobs",
        headers=headers,
        json={
            "task": "script_to_video",
            "title": "Presentazione",
            "script": "Benvenuti nel nostro prodotto.",
            "targetLanguages": ["it-IT", "en-US"],
        },
    )
    assert created.status_code == 200
    payload = created.json()
    assert payload["state"] == "draft"
    assert payload["providerState"] == "not_configured"
    assert payload["created"] is True

    listed = client.get("/v1/studio/jobs", headers=headers)
    assert listed.status_code == 200
    assert [item["jobId"] for item in listed.json()["jobs"]] == [payload["jobId"]]
    assert client.get(
        f"/v1/studio/jobs/{payload['jobId']}", headers=headers
    ).json()["request"]["title"] == "Presentazione"
    assert client.delete(
        f"/v1/studio/jobs/{payload['jobId']}", headers=headers
    ).json()["deleted"] is True


def test_studio_api_prevents_cross_account_draft_access(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from backend import server
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    _user_a, headers_a = _studio_api_user(store, "studio_owner_a")
    _user_b, headers_b = _studio_api_user(store, "studio_owner_b")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setenv("MEDIA_STUDIO_DB", str(tmp_path / "studio.sqlite3"))
    client = TestClient(server.app)

    created = client.post(
        "/v1/studio/jobs", headers=headers_a,
        json={"task": "script_to_video", "script": "Private script"},
    )
    assert created.status_code == 200
    job_id = created.json()["jobId"]
    assert client.get(f"/v1/studio/jobs/{job_id}", headers=headers_b).status_code == 404
    assert client.delete(f"/v1/studio/jobs/{job_id}", headers=headers_b).status_code == 404


def test_studio_api_rejects_personal_avatar_without_consent(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from backend import server
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    _user, headers = _studio_api_user(store, "studio_consent_user")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setenv("MEDIA_STUDIO_DB", str(tmp_path / "studio.sqlite3"))
    response = TestClient(server.app).post(
        "/v1/studio/jobs", headers=headers,
        json={
            "task": "avatar_video", "script": "Welcome",
            "avatarMode": "personal", "avatarConsent": False,
        },
    )
    assert response.status_code == 422


def test_studio_api_requires_account_session():
    from fastapi.testclient import TestClient
    from backend import server

    monkeypatch_client = TestClient(server.app)
    assert monkeypatch_client.get("/v1/studio/capabilities").status_code == 401


def test_studio_api_requires_explicit_review_before_queue_and_lists_queue(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from backend import server
    from backend.accounts import AccountStore

    auth_db = tmp_path / "accounts.sqlite3"
    store = AccountStore(auth_db)
    _user, headers = _studio_api_user(store, "studio_queue_user")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setenv("MEDIA_AUTH_DB", str(auth_db))
    monkeypatch.setenv("MEDIA_STUDIO_DB", str(tmp_path / "studio.sqlite3"))
    monkeypatch.setenv("MEDIA_STUDIO_QUEUE_DB", str(tmp_path / "studio_queue.sqlite3"))
    client = TestClient(server.app)

    created = client.post(
        "/v1/studio/jobs", headers=headers,
        json={"task": "script_to_video", "title": "Mini serie", "script": "Episodio uno"},
    )
    assert created.status_code == 200
    draft_id = created.json()["jobId"]

    # Merely saving a draft must not put it in the processing queue.
    assert client.get("/v1/studio/queue", headers=headers).json()["jobs"] == []

    queued = client.post(
        f"/v1/studio/jobs/{draft_id}/enqueue", headers=headers,
    )
    assert queued.status_code == 200
    payload = queued.json()
    assert payload["state"] == "queued"
    assert payload["sourceDraftId"] == draft_id
    assert payload["providerSubmissionEnabled"] is False
    assert "nessuna chiamata al provider" in payload["message"]

    listed = client.get("/v1/studio/queue", headers=headers)
    assert listed.status_code == 200
    assert len(listed.json()["jobs"]) == 1
    assert listed.json()["jobs"][0]["jobId"] == payload["jobId"]

    # Repeated confirmation is idempotent and does not create a second queue job.
    repeated = client.post(
        f"/v1/studio/jobs/{draft_id}/enqueue", headers=headers,
    )
    assert repeated.status_code == 200
    assert repeated.json()["jobId"] == payload["jobId"]
    assert len(client.get("/v1/studio/queue", headers=headers).json()["jobs"]) == 1
