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
    assert owner_create.status_code == 403
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



def test_owner_role_change_revokes_existing_sessions_and_cannot_change_owner(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("owner_admin", "owner password with enough length")
    user = store.register("ordinary_user", "ordinary password with enough length")
    owner_headers = _headers(store, owner["userId"])
    user_token, _ = store.issue_session(user["userId"])
    client = TestClient(server.app)

    changed = client.post(
        f"/v1/owner/accounts/{user['userId']}/role",
        headers=owner_headers, json={"role": "support"},
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["user"]["role"] == "support"
    assert store.resolve_session(user_token) is None

    owner_change = client.post(
        f"/v1/owner/accounts/{owner['userId']}/role",
        headers=owner_headers, json={"role": "admin"},
    )
    assert owner_change.status_code == 403
    invalid = client.post(
        f"/v1/owner/accounts/{user['userId']}/role",
        headers=owner_headers, json={"role": "owner"},
    )
    assert invalid.status_code == 422


def test_managed_account_must_change_temporary_password_before_media_access(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("owner_admin", "owner password with enough length")
    client = TestClient(server.app)
    owner_headers = _headers(store, owner["userId"])

    created = client.post("/v1/owner/accounts", headers=owner_headers, json={
        "username": "first_login_user",
        "temporaryPassword": "temporary password 123",
        "role": "user",
    })
    assert created.status_code == 200
    login = client.post("/v1/auth/login", json={
        "username": "first_login_user",
        "password": "temporary password 123",
    })
    assert login.status_code == 200
    assert login.json()["user"]["mustChangePassword"] is True
    user_headers = {"Authorization": "Bearer " + login.json()["accessToken"]}

    blocked = client.get("/v1/owner/accounts", headers=user_headers)
    assert blocked.status_code == 428
    changed = client.post("/v1/auth/change-password", headers=user_headers, json={
        "newPassword": "a new secure password 456",
    })
    assert changed.status_code == 200, changed.text
    assert changed.json()["user"]["mustChangePassword"] is False
    assert changed.json()["accessToken"]
    forbidden = client.get(
        "/v1/owner/accounts",
        headers={"Authorization": "Bearer " + changed.json()["accessToken"]},
    )
    assert forbidden.status_code == 403


def test_owner_reset_returns_temporary_password_once_and_requires_rotation(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("owner_admin", "owner password with enough length")
    user = store.register("reset_target", "old password with enough length")
    old_session, _ = store.issue_session(user["userId"])
    owner_headers = _headers(store, owner["userId"])
    client = TestClient(server.app)

    reset = client.post(
        f"/v1/owner/accounts/{user['userId']}/reset-password",
        headers=owner_headers,
    )
    assert reset.status_code == 200
    temporary = reset.json()["temporaryPassword"]
    assert len(temporary) >= 24
    assert store.resolve_session(old_session) is None
    audit = store.list_audit_events(limit=10)
    reset_event = next(event for event in audit if event["action"] == "account.password_reset")
    assert temporary not in str(reset_event)
    login = client.post("/v1/auth/login", json={
        "username": "reset_target", "password": temporary,
    })
    assert login.status_code == 200
    assert login.json()["user"]["mustChangePassword"] is True
    user_headers = {"Authorization": "Bearer " + login.json()["accessToken"]}
    changed = client.post("/v1/auth/change-password", headers=user_headers, json={
        "newPassword": "replacement password 789",
    })
    assert changed.status_code == 200, changed.text

    owner_reset = client.post(
        f"/v1/owner/accounts/{owner['userId']}/reset-password",
        headers=owner_headers,
    )
    assert owner_reset.status_code == 403



def test_owner_can_manage_account_permission_overrides_via_authenticated_api(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("permission_owner", "owner password with enough length")
    user = store.register("permission_target", "user password with enough length")
    owner_headers = _headers(store, owner["userId"])
    user_headers = _headers(store, user["userId"])
    client = TestClient(server.app)

    denied = client.put(
        f"/v1/owner/accounts/{user['userId']}/permissions",
        headers=user_headers,
        json={"permission": "accounts.create", "effect": "allow"},
    )
    assert denied.status_code == 403

    updated = client.put(
        f"/v1/owner/accounts/{user['userId']}/permissions",
        headers=owner_headers,
        json={"permission": "accounts.create", "effect": "allow"},
    )
    assert updated.status_code == 200, updated.text
    assert "accounts.create" in updated.json()["effectivePermissions"]
    assert updated.json()["overrides"][0]["effect"] == "allow"

    viewed = client.get(
        f"/v1/owner/accounts/{user['userId']}/permissions",
        headers=owner_headers,
    )
    assert viewed.status_code == 200
    assert "accounts.create" in viewed.json()["effectivePermissions"]

    removed = client.delete(
        f"/v1/owner/accounts/{user['userId']}/permissions/accounts.create",
        headers=owner_headers,
    )
    assert removed.status_code == 200
    assert removed.json()["removed"] is True
    assert "accounts.create" not in removed.json()["effectivePermissions"]

    invalid = client.put(
        f"/v1/owner/accounts/{user['userId']}/permissions",
        headers=owner_headers,
        json={"permission": "unknown.permission", "effect": "allow"},
    )
    assert invalid.status_code == 422
    audit = store.list_audit_events(20)
    assert any(e["action"] == "account.permission_override" for e in audit)
    assert any(e["action"] == "account.permission_override_removed" for e in audit)


def test_owner_permission_api_does_not_disclose_unknown_account(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("permission_owner", "owner password with enough length")
    client = TestClient(server.app)
    response = client.get(
        "/v1/owner/accounts/" + "f" * 32 + "/permissions",
        headers=_headers(store, owner["userId"]),
    )
    assert response.status_code == 404
