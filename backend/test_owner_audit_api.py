"""Authorization tests for the owner-only audit API."""
from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore


def _token(store, user_id):
    token, _ = store.issue_session(user_id)
    return {"Authorization": f"Bearer {token}"}


def test_only_owner_can_read_audit_events(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("audit_owner", "owner password with enough length")
    user = store.register("audit_reader", "user password with enough length")
    store.record_audit_event(
        owner["userId"], "account.created", user["userId"], {"role": "user"}
    )
    client = TestClient(server.app)

    owner_response = client.get("/v1/owner/audit?limit=10", headers=_token(store, owner["userId"]))
    assert owner_response.status_code == 200
    assert len(owner_response.json()["events"]) == 1
    assert owner_response.json()["events"][0]["action"] == "account.created"

    user_response = client.get("/v1/owner/audit", headers=_token(store, user["userId"]))
    assert user_response.status_code == 403

    anonymous_response = client.get("/v1/owner/audit")
    assert anonymous_response.status_code == 401


def test_audit_api_clamps_limit_and_does_not_expose_to_admin(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("audit_owner", "owner password with enough length")
    admin = store.register("audit_admin", "admin password with enough length")
    with store._connect() as db:
        db.execute("UPDATE accounts SET role='admin' WHERE user_id=?", (admin["userId"],))
    client = TestClient(server.app)

    response = client.get("/v1/owner/audit?limit=10000", headers=_token(store, owner["userId"]))
    assert response.status_code == 200
    assert response.json()["events"] == []

    denied = client.get("/v1/owner/audit", headers=_token(store, admin["userId"]))
    assert denied.status_code == 403


def test_owner_audit_supports_safe_filters_and_offset_pagination(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("audit_filter_owner", "owner password with enough length")
    first = store.register("audit_filter_first", "first password with enough length")
    second = store.register("audit_filter_second", "second password with enough length")
    store.record_audit_event(owner["userId"], "account.created", first["userId"], {"role": "user"})
    store.record_audit_event(owner["userId"], "account.disabled", second["userId"], {"disabled": True})
    store.record_audit_event(owner["userId"], "account.created", second["userId"], {"role": "user"})
    client = TestClient(server.app)
    headers = _token(store, owner["userId"])

    filtered = client.get(
        "/v1/owner/audit?action=account.created&targetUserId=" + second["userId"],
        headers=headers,
    )
    assert filtered.status_code == 200
    assert [event["action"] for event in filtered.json()["events"]] == ["account.created"]
    assert filtered.json()["events"][0]["targetUserId"] == second["userId"]

    page = client.get("/v1/owner/audit?limit=1&offset=1", headers=headers)
    assert page.status_code == 200
    assert len(page.json()["events"]) == 1
    assert page.json()["offset"] == 1
    assert page.json()["hasMore"] is True

    invalid_range = client.get(
        "/v1/owner/audit?since=200&until=100", headers=headers
    )
    assert invalid_range.status_code == 422


def test_audit_integrity_endpoint_verifies_owner_chain_and_rejects_other_roles(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.delenv("MEDIA_AUDIT_HMAC_KEY", raising=False)
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("integrity_owner", "owner password with enough length")
    user = store.register("integrity_user", "user password with enough length")
    admin = store.register("integrity_admin", "admin password with enough length")
    with store._connect() as db:
        db.execute("UPDATE accounts SET role='admin' WHERE user_id=?", (admin["userId"],))
    store.record_audit_event(owner["userId"], "security.integrity_test", user["userId"], {"source": "test"})

    client = TestClient(server.app)
    owner_response = client.get(
        "/v1/owner/audit/integrity", headers=_token(store, owner["userId"])
    )
    assert owner_response.status_code == 200
    assert owner_response.json()["valid"] is True
    assert owner_response.json()["count"] >= 1
    assert owner_response.json()["firstInvalidEventId"] is None
    assert owner_response.json()["algorithm"] == "sha256"
    assert owner_response.json()["keyAvailable"] is True

    for account in (user, admin):
        denied = client.get(
            "/v1/owner/audit/integrity", headers=_token(store, account["userId"])
        )
        assert denied.status_code == 403

    anonymous = client.get("/v1/owner/audit/integrity")
    assert anonymous.status_code == 401


def test_audit_integrity_endpoint_detects_modified_event_details(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.delenv("MEDIA_AUDIT_HMAC_KEY", raising=False)
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("tamper_owner", "owner password with enough length")
    event_id = store.record_audit_event(
        owner["userId"], "security.integrity_test", None, {"source": "original"}
    )
    with store._connect() as db:
        db.execute(
            "UPDATE account_audit_events SET details_json=? WHERE event_id=?",
            ('{"source":"tampered"}', event_id),
        )

    response = TestClient(server.app).get(
        "/v1/owner/audit/integrity", headers=_token(store, owner["userId"])
    )
    assert response.status_code == 200
    assert response.json()["valid"] is False
    assert response.json()["firstInvalidEventId"] == event_id


def test_audit_integrity_endpoint_fails_closed_when_hmac_key_is_missing(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_AUDIT_HMAC_KEY", "test-only-audit-key-with-sufficient-entropy")
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("hmac_owner", "owner password with enough length")
    store.record_audit_event(owner["userId"], "security.integrity_test")
    monkeypatch.delenv("MEDIA_AUDIT_HMAC_KEY")

    response = TestClient(server.app).get(
        "/v1/owner/audit/integrity", headers=_token(store, owner["userId"])
    )
    assert response.status_code == 200
    assert response.json()["valid"] is False
    assert response.json()["keyAvailable"] is False

