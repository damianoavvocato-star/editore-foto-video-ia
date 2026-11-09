"""Owner-only API tests for encrypted backup creation, listing and verification."""
import io
import sqlite3
import tarfile
import uuid

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

def test_backup_retention_endpoint_is_owner_only_and_preview_is_non_destructive(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_BACKUP_DIR", str(tmp_path / "backups"))
    monkeypatch.setenv(
        "MEDIA_BACKUP_ENCRYPTION_KEY",
        Fernet.generate_key().decode("ascii"),
    )
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("retention_owner", "owner password long enough")
    user = store.register("retention_user", "user password long enough")
    client = TestClient(server.app)
    owner_headers = _headers(store, owner["userId"])
    user_headers = _headers(store, user["userId"])

    created = client.post("/v1/owner/backups", headers=owner_headers)
    assert created.status_code == 200
    backup_id = created.json()["backupId"]

    preview = client.post(
        "/v1/owner/backups/retention?retention_days=1&min_keep=1&dry_run=true",
        headers=owner_headers,
    )
    assert preview.status_code == 200
    assert preview.json()["dryRun"] is True
    assert preview.json()["deletedCount"] == 0
    assert (tmp_path / "backups" / f"{backup_id}.mibak").is_file()

    denied = client.post(
        "/v1/owner/backups/retention?dry_run=false",
        headers=user_headers,
    )
    assert denied.status_code == 403
    assert client.post("/v1/owner/backups/retention").status_code == 401

    invalid = client.post(
        "/v1/owner/backups/retention?retention_days=0",
        headers=owner_headers,
    )
    assert invalid.status_code == 422

def test_restore_prepare_endpoint_is_owner_only_and_does_not_replace_live_database(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_BACKUP_DIR", str(tmp_path / "backups"))
    monkeypatch.setenv(
        "MEDIA_BACKUP_ENCRYPTION_KEY",
        Fernet.generate_key().decode("ascii"),
    )
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("restore_owner", "owner password long enough")
    user = store.register("restore_user", "user password long enough")
    client = TestClient(server.app)
    owner_headers = _headers(store, owner["userId"])

    created = client.post("/v1/owner/backups", headers=owner_headers)
    assert created.status_code == 200
    backup_id = created.json()["backupId"]
    store.register("live_only_user", "live only password long")
    before = database.read_bytes()

    prepared = client.post(
        f"/v1/owner/backups/{backup_id}/restore/prepare",
        headers=owner_headers,
    )
    assert prepared.status_code == 200
    assert prepared.json()["prepared"] is True
    assert prepared.json()["applied"] is False
    assert database.read_bytes() == before

    denied = client.post(
        f"/v1/owner/backups/{backup_id}/restore/prepare",
        headers=_headers(store, user["userId"]),
    )
    assert denied.status_code == 403
    assert client.post(
        f"/v1/owner/backups/{backup_id}/restore/prepare"
    ).status_code == 401

def test_restore_staging_retention_endpoint_is_owner_only_and_preview_first(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_BACKUP_DIR", str(tmp_path / "backups"))
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("stage_owner", "owner password long enough")
    user = store.register("stage_user", "user password long enough")
    stage_dir = tmp_path / "backups" / "restore-staging"
    stage_dir.mkdir(parents=True)
    staged = stage_dir / ("d" * 32 + ".sqlite3")
    staged.write_bytes(b"temporary")
    import os
    os.utime(staged, (1000, 1000))
    client = TestClient(server.app)
    url = "/v1/owner/backups/restore-staging/retention?max_age_seconds=300&dry_run=true"

    preview = client.post(url, headers=_headers(store, owner["userId"]))
    assert preview.status_code == 200
    assert preview.json()["eligibleCount"] == 1
    assert preview.json()["deletedCount"] == 0
    assert staged.exists()

    denied = client.post(url, headers=_headers(store, user["userId"]))
    assert denied.status_code == 403
    assert client.post(url).status_code == 401



def test_restore_prepare_api_rejects_incompatible_database_schema(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setenv("MEDIA_AUTH_DB", str(database))
    monkeypatch.setenv("MEDIA_BACKUP_DIR", str(tmp_path / "backups"))
    key = Fernet.generate_key()
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", key.decode("ascii"))
    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", False)
    store = AccountStore(database)
    owner = store.bootstrap_owner("schema_owner", "owner password long enough")

    malformed_database = tmp_path / "malformed.sqlite3"
    with sqlite3.connect(malformed_database) as db:
        db.execute("CREATE TABLE accounts (id TEXT PRIMARY KEY)")
    archive_buffer = io.BytesIO()
    with tarfile.open(fileobj=archive_buffer, mode="w:gz") as archive:
        archive.add(malformed_database, arcname="accounts.sqlite3", recursive=False)
    backup_id = uuid.uuid4().hex
    backup_path = tmp_path / "backups" / f"{backup_id}.mibak"
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    backup_path.write_bytes(Fernet(key).encrypt(archive_buffer.getvalue()))

    before = database.read_bytes()
    response = TestClient(server.app).post(
        f"/v1/owner/backups/{backup_id}/restore/prepare",
        headers=_headers(store, owner["userId"]),
    )
    assert response.status_code == 422
    assert "schema account" in response.json()["detail"]
    assert database.read_bytes() == before

