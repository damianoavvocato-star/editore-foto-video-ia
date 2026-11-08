"""API tests for individual account registration and sessions."""
from fastapi.testclient import TestClient

from backend import server


def test_registration_disabled_by_default(monkeypatch, tmp_path):
    monkeypatch.delenv("MEDIA_ALLOW_REGISTRATION", raising=False)
    monkeypatch.setenv("MEDIA_AUTH_DB", str(tmp_path / "accounts.sqlite3"))
    response = TestClient(server.app).post(
        "/v1/auth/register",
        json={"username": "new_editor", "password": "a sufficiently long password"},
    )
    assert response.status_code == 403


def test_register_login_me_and_logout(monkeypatch, tmp_path):
    monkeypatch.setenv("MEDIA_ALLOW_REGISTRATION", "true")
    monkeypatch.setenv("MEDIA_AUTH_DB", str(tmp_path / "accounts.sqlite3"))
    client = TestClient(server.app)
    registered = client.post(
        "/v1/auth/register",
        json={"username": "new_editor", "password": "a sufficiently long password"},
    )
    assert registered.status_code == 200
    payload = registered.json()
    assert payload["user"]["role"] == "user"
    assert "password" not in payload["user"]
    token = payload["accessToken"]

    me = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["user"]["userId"] == payload["user"]["userId"]

    login = client.post("/v1/auth/login", json={
        "username": "NEW_EDITOR", "password": "a sufficiently long password"
    })
    assert login.status_code == 200
    login_token = login.json()["accessToken"]
    logout = client.delete("/v1/auth/logout", headers={"Authorization": f"Bearer {login_token}"})
    assert logout.status_code == 200
    assert client.get("/v1/auth/me", headers={"Authorization": f"Bearer {login_token}"}).status_code == 401


def test_login_rate_limit_and_generic_failure(monkeypatch, tmp_path):
    monkeypatch.setenv("MEDIA_AUTH_DB", str(tmp_path / "accounts.sqlite3"))
    server.AccountStore().register("new_editor", "a sufficiently long password")
    client = TestClient(server.app)
    for _ in range(10):
        response = client.post("/v1/auth/login", json={
            "username": "new_editor", "password": "wrong password"
        })
        assert response.status_code == 401
    blocked = client.post("/v1/auth/login", json={
        "username": "new_editor", "password": "a sufficiently long password"
    })
    assert blocked.status_code == 429


def test_login_does_not_reveal_unknown_username(monkeypatch, tmp_path):
    monkeypatch.setenv("MEDIA_AUTH_DB", str(tmp_path / "accounts.sqlite3"))
    response = TestClient(server.app).post("/v1/auth/login", json={
        "username": "not_registered", "password": "incorrect password"
    })
    assert response.status_code == 401
    assert response.json()["detail"] == "Credenziali non valide."
