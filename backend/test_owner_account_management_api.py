"""Owner-only account management API tests."""
from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore


def _headers(store, user_id):
    token, _ = store.issue_session(user_id)
    return {"Authorization": f"Bearer {token}"}


def test_owner_can_create_list_disable_and_reenable_managed_accounts(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("owner_admin", "owner password with enough length")
    client = TestClient(server.app)
    headers = _headers(store, owner["userId"])

    created = client.post("/v1/owner/accounts", headers=headers, json={
        "username": "team_member", "temporaryPassword": "temporary password 123",
        "role": "collaborator",
    })
    assert created.status_code == 200
    payload = created.json()
    assert payload["mustChangePassword"] is True
    assert payload["user"]["role"] == "collaborator"
    user_id = payload["user"]["userId"]

    listed = client.get("/v1/owner/accounts", headers=headers)
    assert listed.status_code == 200
    assert any(item["userId"] == user_id for item in listed.json()["accounts"])
    assert "password_hash" not in str(listed.json())

    user_token, _ = store.issue_session(user_id)
    disabled = client.post(f"/v1/owner/accounts/{user_id}/disable", headers=headers)
    assert disabled.status_code == 200
    assert disabled.json()["user"]["disabled"] is True
    assert store.resolve_session(user_token) is None

    enabled = client.post(f"/v1/owner/accounts/{user_id}/enable", headers=headers)
    assert enabled.status_code == 200
    assert enabled.json()["user"]["disabled"] is False


def test_non_owner_cannot_manage_accounts_and_owner_cannot_create_owner(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("owner_admin", "owner password with enough length")
    user = store.register("ordinary_user", "ordinary password with enough length")
    client = TestClient(server.app)
    owner_headers = _headers(store, owner["userId"])
    user_headers = _headers(store, user["userId"])

    denied = client.get("/v1/owner/accounts", headers=user_headers)
    assert denied.status_code == 403
    denied_create = client.post("/v1/owner/accounts", headers=user_headers, json={
        "username": "new_member", "temporaryPassword": "temporary password 123",
        "role": "support",
    })
    assert denied_create.status_code == 403

    owner_create = client.post("/v1/owner/accounts", headers=owner_headers, json={
        "username": "second_owner", "temporaryPassword": "temporary password 123",
        "role": "owner",
    })
    assert owner_create.status_code == 422
    assert store.list_accounts(20)[0]["role"] in {"owner", "user"}


def test_owner_management_cannot_disable_owner_and_unknown_user_is_not_found(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("owner_admin", "owner password with enough length")
    headers = _headers(store, owner["userId"])
    client = TestClient(server.app)

    denied = client.post(
        f"/v1/owner/accounts/{owner['userId']}/disable", headers=headers
    )
    assert denied.status_code == 403
    missing = client.post(
        "/v1/owner/accounts/" + "f" * 32 + "/disable", headers=headers
    )
    assert missing.status_code == 404
