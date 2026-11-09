"""Owner-only API tests for encrypted backup creation, listing and verification."""
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from backend import server
from backend.accounts import AccountStore


def _headers(store, user_id):
    token, _ = store.issue_session(user_id)
    return {"Authorization": f"Bearer {token}"}


def test_backup_endpoints_are_owner_only_and_verify_created_snapshot(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_BACKUP_DIR", str(tmp_path / "backups"))
    monkeypatch.setenv(
        "MEDIA_BACKUP_ENCRYPTION_KEY",
        Fernet.generate_key().decode("ascii"),
    )
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("backup_owner", "owner password long enough")
    user = store.register("backup_user", "user password long enough")
    client = TestClient(server.app)

    created = client.post("/v1/owner/backups", headers=_headers(store, owner["userId"]))
    assert created.status_code == 200
    backup = created.json()
    assert backup["encrypted"] is True
    assert backup["sizeBytes"] > 0

    listed = client.get("/v1/owner/backups?limit=10", headers=_headers(store, owner["userId"]))
    assert listed.status_code == 200
    assert [row["backupId"] for row in listed.json()["backups"]] == [backup["backupId"]]

    verified = client.post(
        f"/v1/owner/backups/{backup['backupId']}/verify",
        headers=_headers(store, owner["userId"]),
    )
    assert verified.status_code == 200
    assert verified.json()["valid"] is True
    assert verified.json()["databaseIntegrity"] == "ok"

    assert client.get("/v1/owner/backups", headers=_headers(store, user["userId"])).status_code == 403
    assert client.post("/v1/owner/backups").status_code == 401


def test_backup_creation_fails_closed_without_encryption_key(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_BACKUP_DIR", str(tmp_path / "backups"))
    monkeypatch.delenv("MEDIA_BACKUP_ENCRYPTION_KEY", raising=False)
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("backup_owner", "owner password long enough")
    response = TestClient(server.app).post(
        "/v1/owner/backups",
        headers=_headers(store, owner["userId"]),
    )
    assert response.status_code == 503
    assert "MEDIA_BACKUP_ENCRYPTION_KEY" in response.json()["detail"]
