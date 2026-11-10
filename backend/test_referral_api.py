from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore
from backend.entitlements import EntitlementStore
from backend.usage_store import UsageStore


def test_referral_api_requires_session_and_claims_code_once(tmp_path, monkeypatch):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    inviter = store.register("api_inviter", "inviter password long enough")
    invitee = store.register("api_invitee", "invitee password long enough")
    another = store.register("api_another", "another password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)

    assert client.get("/v1/account/referrals").status_code == 401

    def headers(user_id):
        token, _ = store.issue_session(user_id)
        return {"Authorization": f"Bearer {token}"}

    inviter_headers = headers(inviter["userId"])
    invitee_headers = headers(invitee["userId"])
    another_headers = headers(another["userId"])

    code_response = client.get("/v1/account/referrals", headers=inviter_headers)
    assert code_response.status_code == 200
    code = code_response.json()["code"]
    assert len(code) == 10

    self_claim = client.post(
        "/v1/account/referrals/claim",
        headers=inviter_headers,
        json={"code": code},
    )
    assert self_claim.status_code == 422

    claim = client.post(
        "/v1/account/referrals/claim",
        headers=invitee_headers,
        json={"code": code},
    )
    assert claim.status_code == 200
    assert claim.json()["status"] == "pending"
    assert claim.json()["rewardDays"] == 30

    duplicate = client.post(
        "/v1/account/referrals/claim",
        headers=invitee_headers,
        json={"code": code},
    )
    assert duplicate.status_code == 422

    history = client.get("/v1/account/referrals/history", headers=invitee_headers)
    assert history.status_code == 200
    assert history.json()["claims"][0]["role"] == "invitee"
    assert history.json()["claims"][0]["status"] == "pending"

    invalid = client.post(
        "/v1/account/referrals/claim",
        headers=another_headers,
        json={"code": "NOTREAL123"},
    )
    assert invalid.status_code == 422

    unicode_code = client.post(
        "/v1/account/referrals/claim",
        headers=another_headers,
        json={"code": "ÀB12CD34"},
    )
    assert unicode_code.status_code == 422

    short_code = client.post(
        "/v1/account/referrals/claim",
        headers=another_headers,
        json={"code": "ABC"},
    )
    assert short_code.status_code == 422



def test_account_usage_endpoint_requires_auth_and_returns_server_quota(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    store = AccountStore(database)
    user = store.register("quota_user", "quota password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setattr(server, "_entitlement_store", lambda: EntitlementStore(database))
    monkeypatch.setattr(server, "_usage_store", lambda: UsageStore(database))
    client = TestClient(server.app)

    assert client.get("/v1/account/usage").status_code == 401
    token, _ = store.issue_session(user["userId"])
    headers = {"Authorization": f"Bearer {token}"}
    summary = client.get("/v1/account/usage", headers=headers)
    assert summary.status_code == 200
    data = summary.json()
    assert data["limit"] == server._ai_monthly_limit(False)
    assert data["used"] == 0
    assert data["remaining"] == data["limit"]
    assert data["exhausted"] is False



def test_credit_api_is_owner_only_and_balance_is_private(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    store = AccountStore(database)
    owner = store.bootstrap_owner("credit_owner", "owner password long enough")
    user = store.register("credit_user", "user password long enough")
    other = store.register("credit_other", "other password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)

    def headers(user_id):
        token, _ = store.issue_session(user_id)
        return {"Authorization": f"Bearer {token}"}

    owner_headers = headers(owner["userId"])
    user_headers = headers(user["userId"])
    other_headers = headers(other["userId"])

    assert client.get("/v1/account/credits").status_code == 401
    assert client.get("/v1/account/credits", headers=user_headers).json()["balance"]["balance"] == 0

    denied = client.post(
        f"/v1/owner/accounts/{user['userId']}/credits",
        headers=user_headers,
        json={"amount": 50, "referenceId": "launch-bonus", "reason": "test"},
    )
    assert denied.status_code == 403

    grant = client.post(
        f"/v1/owner/accounts/{user['userId']}/credits",
        headers=owner_headers,
        json={"amount": 50, "referenceId": "launch-bonus", "reason": "beta bonus"},
    )
    assert grant.status_code == 200
    assert grant.json()["balance"] == 50

    repeated = client.post(
        f"/v1/owner/accounts/{user['userId']}/credits",
        headers=owner_headers,
        json={"amount": 50, "referenceId": "launch-bonus", "reason": "beta bonus"},
    )
    assert repeated.status_code == 200
    assert repeated.json()["applied"] is False

    assert client.get("/v1/account/credits", headers=user_headers).json()["balance"]["balance"] == 50
    assert client.get("/v1/account/credits", headers=other_headers).json()["balance"]["balance"] == 0
