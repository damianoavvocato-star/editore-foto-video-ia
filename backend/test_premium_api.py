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



def test_family_invitation_is_one_time_and_requires_authenticated_accounts(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    accounts = AccountStore(database)
    owner = accounts.bootstrap_owner("family_owner", "owner password with enough length")
    member = accounts.register("family_member", "member password with enough length")
    stranger = accounts.register("family_stranger", "stranger password with enough length")
    entitlements = server._entitlement_store()
    entitlements.grant("owner", owner["userId"], owner["userId"], "family")
    client = TestClient(server.app)

    unauthenticated = client.post("/v1/account/family/invitations")
    assert unauthenticated.status_code == 401
    invitation = client.post(
        "/v1/account/family/invitations",
        headers=_headers(accounts, owner["userId"]),
    )
    assert invitation.status_code == 200, invitation.text
    payload = invitation.json()
    assert payload["token"]

    accepted = client.post(
        "/v1/account/family/invitations/accept",
        headers=_headers(accounts, member["userId"]),
        json={"token": payload["token"]},
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["accepted"] is True
    assert entitlements.has_premium(member["userId"])

    replay = client.post(
        "/v1/account/family/invitations/accept",
        headers=_headers(accounts, stranger["userId"]),
        json={"token": payload["token"]},
    )
    assert replay.status_code == 422
    assert not entitlements.has_premium(stranger["userId"])


def test_family_owner_can_list_and_remove_members_but_member_cannot(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    accounts = AccountStore(database)
    owner = accounts.bootstrap_owner("family_owner", "owner password with enough length")
    member = accounts.register("family_member", "member password with enough length")
    entitlements = server._entitlement_store()
    entitlements.grant("owner", owner["userId"], owner["userId"], "family")
    family_id = entitlements.create_family_for_grant_owner(owner["userId"])
    entitlements.add_family_member(family_id, owner["userId"], member["userId"])
    client = TestClient(server.app)
    owner_headers = _headers(accounts, owner["userId"])
    member_headers = _headers(accounts, member["userId"])

    roster = client.get("/v1/account/family", headers=owner_headers)
    assert roster.status_code == 200
    assert roster.json()["familyId"] == family_id
    assert roster.json()["isOwner"] is True
    assert {item["user_id"] for item in roster.json()["members"]} == {
        owner["userId"], member["userId"]
    }

    denied = client.delete(
        f"/v1/account/family/members/{owner['userId']}",
        headers=member_headers,
    )
    assert denied.status_code == 403

    removed = client.delete(
        f"/v1/account/family/members/{member['userId']}",
        headers=owner_headers,
    )
    assert removed.status_code == 200
    assert removed.json()["removed"] is True
    assert not entitlements.has_premium(member["userId"])
    assert client.get("/v1/account/family", headers=member_headers).json()["familyId"] is None

    actions = [event["action"] for event in accounts.list_audit_events(20)]
    assert "family.member_removed" in actions


def test_family_owner_can_list_and_revoke_pending_invitation_without_token_leak(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    accounts = AccountStore(database)
    owner = accounts.bootstrap_owner("family_invite_owner", "owner password with enough length")
    member = accounts.register("family_invite_member", "member password with enough length")
    entitlements = server._entitlement_store()
    entitlements.grant("owner", owner["userId"], owner["userId"], "family")
    family_id = entitlements.create_family_for_grant_owner(owner["userId"])
    invite = entitlements.create_family_invitation(family_id, owner["userId"])
    client = TestClient(server.app)
    owner_headers = _headers(accounts, owner["userId"])
    member_headers = _headers(accounts, member["userId"])

    denied = client.get("/v1/account/family/invitations", headers=member_headers)
    assert denied.status_code == 403
    listed = client.get("/v1/account/family/invitations", headers=owner_headers)
    assert listed.status_code == 200
    assert len(listed.json()["invitations"]) == 1
    metadata = listed.json()["invitations"][0]
    assert metadata["invitation_id"] == invite["invitationId"]
    assert "token" not in metadata and "token_hash" not in metadata

    revoked = client.delete(
        f"/v1/account/family/invitations/{invite['invitationId']}",
        headers=owner_headers,
    )
    assert revoked.status_code == 200
    replay = client.post(
        "/v1/account/family/invitations/accept",
        headers=member_headers,
        json={"token": invite["token"]},
    )
    assert replay.status_code == 422
    actions = [event["action"] for event in accounts.list_audit_events(20)]
    assert "family.invitation_revoked" in actions
