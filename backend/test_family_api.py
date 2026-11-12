from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore
from backend.entitlements import EntitlementStore


def test_family_invitation_lifecycle_and_access_control(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    accounts = AccountStore(database)
    owner = accounts.register("family_owner", "owner password long enough")
    member = accounts.register("family_member", "member password long enough")
    stranger = accounts.register("family_stranger", "stranger password long enough")
    entitlements = EntitlementStore(database)
    entitlements.grant("owner", "platform_owner", owner["userId"], "family")

    monkeypatch.setattr(server, "_account_store", lambda: accounts)
    monkeypatch.setattr(server, "_entitlement_store", lambda: entitlements)
    client = TestClient(server.app)

    def headers(user_id):
        token, _ = accounts.issue_session(user_id)
        return {"Authorization": f"Bearer {token}"}

    owner_headers = headers(owner["userId"])
    member_headers = headers(member["userId"])
    stranger_headers = headers(stranger["userId"])

    assert client.post("/v1/account/family/invitations").status_code == 401

    created = client.post(
        "/v1/account/family/invitations", headers=owner_headers
    )
    assert created.status_code == 200
    invitation = created.json()
    assert invitation["token"]
    assert invitation["invitationId"]
    assert invitation["expiresAt"]

    family = client.get("/v1/account/family", headers=owner_headers)
    assert family.status_code == 200
    family_data = family.json()
    assert family_data["isOwner"] is True
    assert family_data["ownerUserId"] == owner["userId"]
    assert family_data["seatLimit"] >= 2
    assert [row["user_id"] for row in family_data["members"]] == [owner["userId"]]

    invitations = client.get(
        "/v1/account/family/invitations", headers=owner_headers
    )
    assert invitations.status_code == 200
    assert len(invitations.json()["invitations"]) == 1
    assert "token" not in invitations.json()["invitations"][0]

    denied_list = client.get(
        "/v1/account/family/invitations", headers=stranger_headers
    )
    assert denied_list.status_code == 403

    accepted = client.post(
        "/v1/account/family/invitations/accept",
        headers=member_headers,
        json={"token": invitation["token"]},
    )
    assert accepted.status_code == 200
    assert accepted.json()["accepted"] is True

    duplicate = client.post(
        "/v1/account/family/invitations/accept",
        headers=headers(stranger["userId"]),
        json={"token": invitation["token"]},
    )
    assert duplicate.status_code == 422

    member_family = client.get("/v1/account/family", headers=member_headers)
    assert member_family.status_code == 200
    assert member_family.json()["isOwner"] is False
    assert len(member_family.json()["members"]) == 2

    removed = client.delete(
        f"/v1/account/family/members/{member['userId']}",
        headers=owner_headers,
    )
    assert removed.status_code == 200
    assert removed.json()["removed"] is True
    assert client.get("/v1/account/family", headers=member_headers).json()["familyId"] is None


def test_family_creation_requires_active_family_entitlement(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    accounts = AccountStore(database)
    user = accounts.register("individual_user", "individual password long enough")
    entitlements = EntitlementStore(database)
    entitlements.grant("owner", "platform_owner", user["userId"], "premium")
    monkeypatch.setattr(server, "_account_store", lambda: accounts)
    monkeypatch.setattr(server, "_entitlement_store", lambda: entitlements)
    token, _ = accounts.issue_session(user["userId"])

    response = TestClient(server.app).post(
        "/v1/account/family/invitations",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403
