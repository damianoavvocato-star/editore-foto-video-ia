from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore


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
