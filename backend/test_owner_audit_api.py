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
