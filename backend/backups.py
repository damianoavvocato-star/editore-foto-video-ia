"""Encrypted, integrity-checkable SQLite account backups.

Backups contain the account/entitlement/team database only. Media asset storage,
remote replication, retention policy and restore orchestration remain separate
release requirements.
"""
from __future__ import annotations

import hashlib
import io
import os
import re
import sqlite3
import tarfile
import tempfile
import time
import uuid
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken


class BackupError(ValueError):
    pass


class BackupStore:
    def __init__(self, database: str | Path, directory: str | Path):
        self.database = Path(database).expanduser().resolve()
        self.directory = Path(directory).expanduser().resolve()
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            os.chmod(self.directory, 0o700)
        except OSError:
            pass

    @staticmethod
    def _fernet() -> Fernet:
        key = os.getenv("MEDIA_BACKUP_ENCRYPTION_KEY", "").strip()
        if not key:
            raise BackupError("Configurare MEDIA_BACKUP_ENCRYPTION_KEY per creare backup cifrati.")
        try:
            return Fernet(key.encode("ascii"))
        except (ValueError, UnicodeEncodeError) as exc:
            raise BackupError("MEDIA_BACKUP_ENCRYPTION_KEY non è una chiave Fernet valida.") from exc

    @staticmethod
    def _valid_id(backup_id: str) -> bool:
        return isinstance(backup_id, str) and re.fullmatch(r"[a-f0-9]{32}", backup_id) is not None

    def create(self) -> dict:
        if not self.database.is_file():
            raise BackupError("Database account non trovato.")
        fernet = self._fernet()
        with tempfile.TemporaryDirectory(prefix="magiciaedit-backup-") as temporary:
            snapshot = Path(temporary) / "accounts.sqlite3"
            with sqlite3.connect(self.database, timeout=15) as source:
                with sqlite3.connect(snapshot) as destination:
                    source.backup(destination)
            integrity = sqlite3.connect(snapshot)
            try:
                check = integrity.execute("PRAGMA quick_check").fetchone()[0]
            finally:
                integrity.close()
            if check != "ok":
                raise BackupError("Il database sorgente non supera il controllo di integrità.")
            archive_buffer = io.BytesIO()
            with tarfile.open(fileobj=archive_buffer, mode="w:gz") as archive:
                archive.add(snapshot, arcname="accounts.sqlite3", recursive=False)
            encrypted = fernet.encrypt(archive_buffer.getvalue())
        backup_id = uuid.uuid4().hex
        destination = self.directory / f"{backup_id}.mibak"
        with destination.open("xb") as output:
            output.write(encrypted)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.chmod(destination, 0o600)
        except OSError:
            pass
        return {
            "backupId": backup_id,
            "createdAt": int(time.time()),
            "sizeBytes": len(encrypted),
            "sha256": hashlib.sha256(encrypted).hexdigest(),
            "encrypted": True,
            "includes": ["accounts", "entitlements", "team metadata", "audit"],
        }

    def list_backups(self, limit: int = 50) -> list[dict]:
        limit = max(1, min(100, limit if isinstance(limit, int) and not isinstance(limit, bool) else 50))
        files = sorted(self.directory.glob("*.mibak"), key=lambda item: item.stat().st_mtime, reverse=True)[:limit]
        result = []
        for path in files:
            backup_id = path.stem
            if not self._valid_id(backup_id) or not path.is_file() or path.is_symlink():
                continue
            data = path.read_bytes()
            result.append({
                "backupId": backup_id,
                "createdAt": int(path.stat().st_mtime),
                "sizeBytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "encrypted": True,
            })
        return result


    def prune(
        self,
        retention_days: int = 90,
        min_keep: int = 3,
        dry_run: bool = True,
        now: int | float | None = None,
    ) -> dict:
        """Preview or remove expired backups while always preserving the newest set."""
        if not isinstance(retention_days, int) or isinstance(retention_days, bool) or not 1 <= retention_days <= 3650:
            raise BackupError("Periodo di conservazione non valido.")
        if not isinstance(min_keep, int) or isinstance(min_keep, bool) or not 1 <= min_keep <= 100:
            raise BackupError("Numero minimo di backup da conservare non valido.")
        if not isinstance(dry_run, bool):
            raise BackupError("Modalità anteprima non valida.")
        timestamp = time.time() if now is None else float(now)
        cutoff = timestamp - retention_days * 24 * 60 * 60
        candidates = []
        for path in self.directory.iterdir():
            if (
                not self._valid_id(path.stem)
                or path.suffix != ".mibak"
                or path.is_symlink()
                or not path.is_file()
            ):
                continue
            try:
                stat = path.stat(follow_symlinks=False)
            except OSError:
                continue
            candidates.append((stat.st_mtime, path))
        candidates.sort(key=lambda item: item[0], reverse=True)
        expired = [
            (modified, path)
            for index, (modified, path) in enumerate(candidates)
            if index >= min_keep and modified < cutoff
        ]
        removed = []
        if not dry_run:
            for _, path in expired:
                try:
                    # Re-check the directory entry immediately before deletion.
                    if path.is_symlink() or not path.is_file():
                        continue
                    path.unlink()
                    removed.append(path.stem)
                except FileNotFoundError:
                    continue
        return {
            "dryRun": dry_run,
            "retentionDays": retention_days,
            "minimumToKeep": min_keep,
            "eligibleCount": len(expired),
            "eligibleBackupIds": [path.stem for _, path in expired],
            "deletedCount": len(removed),
            "deletedBackupIds": removed,
        }


    def verify(self, backup_id: str) -> dict:
        if not self._valid_id(backup_id):
            raise BackupError("Identificativo backup non valido.")
        path = self.directory / f"{backup_id}.mibak"
        if not path.is_file() or path.is_symlink():
            raise BackupError("Backup non trovato.")
        encrypted = path.read_bytes()
        try:
            archive_bytes = self._fernet().decrypt(encrypted)
        except InvalidToken as exc:
            raise BackupError("Backup non verificabile: chiave errata o file alterato.") from exc
        try:
            with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
                members = archive.getmembers()
                if len(members) != 1 or members[0].name != "accounts.sqlite3" or not members[0].isfile():
                    raise BackupError("Contenuto backup non valido.")
                extracted = archive.extractfile(members[0])
                if extracted is None:
                    raise BackupError("Database nel backup non leggibile.")
                database_bytes = extracted.read(512 * 1024 * 1024 + 1)
                if len(database_bytes) > 512 * 1024 * 1024:
                    raise BackupError("Backup oltre la dimensione massima consentita.")
        except (tarfile.TarError, OSError) as exc:
            raise BackupError("Archivio backup danneggiato.") from exc
        with tempfile.TemporaryDirectory(prefix="magiciaedit-verify-") as temporary:
            snapshot = Path(temporary) / "verified.sqlite3"
            snapshot.write_bytes(database_bytes)
            with sqlite3.connect(snapshot) as db:
                result = db.execute("PRAGMA quick_check").fetchone()[0]
                tables = {row[0] for row in db.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()}
            if result != "ok" or "accounts" not in tables:
                raise BackupError("Database del backup non integro o non riconosciuto.")
        return {
            "backupId": backup_id,
            "valid": True,
            "encrypted": True,
            "databaseIntegrity": result,
            "sizeBytes": len(encrypted),
            "sha256": hashlib.sha256(encrypted).hexdigest(),
        }
