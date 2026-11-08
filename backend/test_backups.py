import pytest
from cryptography.fernet import Fernet

from backend.accounts import AccountStore
from backend.backups import BackupError, BackupStore


def test_backup_is_encrypted_and_database_integrity_can_be_verified(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    accounts = AccountStore(database)
    accounts.register("backup_user", "backup user password long")
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")

    created = backups.create()
    assert created["encrypted"] is True
    assert created["sizeBytes"] > 0
    assert len(created["sha256"]) == 64
    assert backups.verify(created["backupId"])["valid"] is True
    assert backups.list_backups()[0]["backupId"] == created["backupId"]


def test_backup_fails_closed_without_encryption_key(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.delenv("MEDIA_BACKUP_ENCRYPTION_KEY", raising=False)
    backups = BackupStore(database, tmp_path / "backups")
    with pytest.raises(BackupError, match="ENCRYPTION_KEY"):
        backups.create()


def test_backup_verification_detects_ciphertext_tampering(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    created = backups.create()
    path = tmp_path / "backups" / f"{created['backupId']}.mibak"
    content = bytearray(path.read_bytes())
    content[-1] ^= 1
    path.write_bytes(content)
    with pytest.raises(BackupError, match="alterato"):
        backups.verify(created["backupId"])
