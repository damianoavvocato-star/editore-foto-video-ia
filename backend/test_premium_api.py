"""Authenticated Premium entitlement and owner grant API tests."""
from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore


def _headers(store, user_id):
    token, _ = store.issue_session(user_id)
    return {"Authorization": f"Bearer {token}"}


def test_account_can_read_only_its_own_premium_entitlement(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("premium_owner", "owner password with enough length")
    user = store.register("premium_user", "user password with enough length")
    client = TestClient(server.app)

    anonymous = client.get("/v1/account/entitlement")
    assert anonymous.status_code == 401
    free = client.get("/v1/account/entitlement", headers=_headers(store, user["userId"]))
    assert free.status_code == 200
    assert free.json() == {
        "userId": user["userId"], "tier": "free", "isPremium": False,
        "plan": None, "validUntil": None, "source": None,
    }

    import time
    expires_at = int(time.time()) + 3600
    server._entitlement_store().grant(
        "owner", owner["userId"], user["userId"], "premium",
        expires_at=expires_at,
    )
    active = client.get("/v1/account/entitlement", headers=_headers(store, user["userId"]))
    assert active.status_code == 200
    assert active.json()["isPremium"] is True
    assert active.json()["plan"] == "premium"
    assert active.json()["source"] == "promotion"
    assert active.json()["validUntil"].endswith("Z")


def test_owner_can_grant_list_and_revoke_premium_with_audit(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("premium_owner", "owner password with enough length")
    user = store.register("premium_target", "user password with enough length")
    client = TestClient(server.app)
    owner_headers = _headers(store, owner["userId"])

    denied = client.post(
        f"/v1/owner/accounts/{user['userId']}/premium-grants",
        headers=_headers(store, user["userId"]),
        json={"plan": "premium", "reason": "beta"},
    )
    assert denied.status_code == 403

    created = client.post(
        f"/v1/owner/accounts/{user['userId']}/premium-grants",
        headers=owner_headers,
        json={"plan": "premium", "reason": "beta grant"},
    )
    assert created.status_code == 200, created.text
    grant_id = created.json()["grantId"]
    assert created.json()["plan"] == "premium"

    listed = client.get(
        f"/v1/owner/accounts/{user['userId']}/premium-grants",
        headers=owner_headers,
    )
    assert listed.status_code == 200
    assert listed.json()["grants"][0]["grant_id"] == grant_id

    status = client.get(
        "/v1/account/entitlement", headers=_headers(store, user["userId"])
    )
    assert status.json()["isPremium"] is True

    revoked = client.delete(
        f"/v1/owner/accounts/{user['userId']}/premium-grants/{grant_id}",
        headers=owner_headers,
    )
    assert revoked.status_code == 200
    assert revoked.json()["revoked"] is True
    status = client.get(
        "/v1/account/entitlement", headers=_headers(store, user["userId"])
    )
    assert status.json()["isPremium"] is False

    actions = [event["action"] for event in store.list_audit_events(20)]
    assert "premium.grant_created" in actions
    assert "premium.grant_revoked" in actions


def test_premium_grant_rejects_unknown_user_and_invalid_expiry(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("premium_owner", "owner password with enough length")
    client = TestClient(server.app)
    headers = _headers(store, owner["userId"])

    missing = client.post(
        "/v1/owner/accounts/" + "f" * 32 + "/premium-grants",
        headers=headers, json={"plan": "premium"},
    )
    assert missing.status_code == 404

    user = store.register("premium_invalid", "user password with enough length")
    expired = client.post(
        f"/v1/owner/accounts/{user['userId']}/premium-grants",
        headers=headers,
        json={"plan": "premium", "expiresAt": 1},
    )
    assert expired.status_code == 422
