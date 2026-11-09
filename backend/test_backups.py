import io
import sqlite3
import tarfile
import uuid

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

def test_retention_preview_and_prune_preserve_minimum_newest_backups(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    created = []
    for index in range(5):
        result = backups.create()
        path = tmp_path / "backups" / f"{result['backupId']}.mibak"
        path.touch()
        import os
        os.utime(path, (1000 + index, 1000 + index))
        created.append(result["backupId"])

    preview = backups.prune(retention_days=1, min_keep=2, dry_run=True, now=200000)
    assert preview["eligibleCount"] == 3
    assert preview["deletedCount"] == 0
    assert len(backups.list_backups()) == 5

    applied = backups.prune(retention_days=1, min_keep=2, dry_run=False, now=200000)
    assert applied["deletedCount"] == 3
    remaining = {item["backupId"] for item in backups.list_backups()}
    assert remaining == set(created[-2:])


def test_retention_rejects_invalid_policy_and_does_not_follow_symlinks(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    with pytest.raises(BackupError):
        backups.prune(retention_days=0)
    with pytest.raises(BackupError):
        backups.prune(min_keep=0)

    outside = tmp_path / "outside.mibak"
    outside.write_bytes(b"do-not-delete")
    link = tmp_path / "backups" / ("a" * 32 + ".mibak")
    try:
        link.symlink_to(outside)
    except (OSError, NotImplementedError):
        pytest.skip("Symlinks are not available on this platform")
    result = backups.prune(retention_days=1, min_keep=1, dry_run=False, now=200000)
    assert result["deletedCount"] == 0
    assert outside.read_bytes() == b"do-not-delete"

def test_restore_preparation_stages_verified_database_without_overwriting_live_database(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    accounts = AccountStore(database)
    accounts.register("restore_user", "restore user password long")
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    created = backups.create()

    accounts.register("new_live_user", "new live user password long")
    before = database.read_bytes()
    prepared = backups.prepare_restore(created["backupId"])

    assert prepared["prepared"] is True
    assert prepared["applied"] is False
    assert prepared["databaseIntegrity"] == "ok"
    assert "accounts" in prepared["tables"]
    assert database.read_bytes() == before

    staged = tmp_path / "backups" / "restore-staging" / f"{prepared['restoreStageId']}.sqlite3"
    assert staged.is_file()
    with sqlite3.connect(staged) as restored:
        usernames = {row[0] for row in restored.execute("SELECT username FROM accounts")}
    assert "restore_user" in usernames
    assert "new_live_user" not in usernames


def test_restore_preparation_rejects_tampered_or_unknown_backup(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    with pytest.raises(BackupError, match="non trovato"):
        backups.prepare_restore("a" * 32)
    created = backups.create()
    path = tmp_path / "backups" / f"{created['backupId']}.mibak"
    damaged = bytearray(path.read_bytes())
    damaged[-1] ^= 1
    path.write_bytes(damaged)
    with pytest.raises(BackupError, match="alterato"):
        backups.prepare_restore(created["backupId"])


def test_restore_preparation_rejects_database_with_incompatible_account_schema(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    key = Fernet.generate_key()
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", key.decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")

    malformed_database = tmp_path / "malformed.sqlite3"
    with sqlite3.connect(malformed_database) as db:
        db.execute("CREATE TABLE accounts (id TEXT PRIMARY KEY)")
    archive_buffer = io.BytesIO()
    with tarfile.open(fileobj=archive_buffer, mode="w:gz") as archive:
        archive.add(malformed_database, arcname="accounts.sqlite3", recursive=False)
    backup_id = uuid.uuid4().hex
    backup_path = tmp_path / "backups" / f"{backup_id}.mibak"
    backup_path.write_bytes(Fernet(key).encrypt(archive_buffer.getvalue()))

    with pytest.raises(BackupError, match="schema account"):
        backups.prepare_restore(backup_id)

def test_restore_staging_expiry_preview_and_delete_are_bounded(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    stage_dir = tmp_path / "backups" / "restore-staging"
    stage_dir.mkdir()
    old_id = "a" * 32
    fresh_id = "b" * 32
    old_file = stage_dir / f"{old_id}.sqlite3"
    fresh_file = stage_dir / f"{fresh_id}.sqlite3"
    old_file.write_bytes(b"old-stage")
    fresh_file.write_bytes(b"fresh-stage")
    import os
    os.utime(old_file, (1000, 1000))
    os.utime(fresh_file, (99000, 99000))

    preview = backups.prune_restore_staging(
        max_age_seconds=3600, dry_run=True, now=100000
    )
    assert preview["eligibleStageIds"] == [old_id]
    assert preview["deletedCount"] == 0
    assert old_file.exists()

    applied = backups.prune_restore_staging(
        max_age_seconds=3600, dry_run=False, now=100000
    )
    assert applied["deletedStageIds"] == [old_id]
    assert not old_file.exists()
    assert fresh_file.exists()


def test_restore_staging_expiry_ignores_symlinks_and_rejects_invalid_policy(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    AccountStore(database)
    monkeypatch.setenv("MEDIA_BACKUP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    backups = BackupStore(database, tmp_path / "backups")
    stage_dir = tmp_path / "backups" / "restore-staging"
    stage_dir.mkdir()
    outside = tmp_path / "outside.sqlite3"
    outside.write_bytes(b"keep")
    link = stage_dir / ("c" * 32 + ".sqlite3")
    try:
        link.symlink_to(outside)
    except (OSError, NotImplementedError):
        pytest.skip("Symlinks are not available on this platform")
    with pytest.raises(BackupError):
        backups.prune_restore_staging(max_age_seconds=1)
    result = backups.prune_restore_staging(
        max_age_seconds=300, dry_run=False, now=100000
    )
    assert result["deletedCount"] == 0
    assert outside.read_bytes() == b"keep"

