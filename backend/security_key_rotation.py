"""Offline atomic rotation for encrypted owner TOTP seeds.

Set MEDIA_AUTH_DB, MEDIA_TOTP_OLD_ENCRYPTION_KEY and
MEDIA_TOTP_NEW_ENCRYPTION_KEY in a protected operator environment, then run
`python -m backend.security_key_rotation`. Never pass keys as command-line
arguments or print them to logs.
"""
from __future__ import annotations

import os
import sqlite3
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken

from backend.accounts import SecurityConfigurationError


def rotate_totp_encryption_key(
    database: str | Path, old_key: str | bytes, new_key: str | bytes
) -> int:
    try:
        old_cipher = Fernet(old_key.encode("ascii") if isinstance(old_key, str) else old_key)
        new_cipher = Fernet(new_key.encode("ascii") if isinstance(new_key, str) else new_key)
    except (TypeError, ValueError, UnicodeEncodeError) as exc:
        raise SecurityConfigurationError("Chiave Fernet non valida.") from exc
    old_raw = old_key.encode("ascii") if isinstance(old_key, str) else old_key
    new_raw = new_key.encode("ascii") if isinstance(new_key, str) else new_key
    if old_raw == new_raw:
        raise SecurityConfigurationError("La nuova chiave deve essere diversa da quella attuale.")

    path = str(Path(database).expanduser().resolve())
    db = sqlite3.connect(path, timeout=30)
    try:
        db.row_factory = sqlite3.Row
        db.execute("BEGIN IMMEDIATE")
        columns = {
            row["name"] for row in db.execute("PRAGMA table_info(accounts)").fetchall()
        }
        if not {"totp_secret_enc", "totp_pending_secret_enc"}.issubset(columns):
            raise SecurityConfigurationError("Schema TOTP non inizializzato.")
        rows = db.execute(
            """SELECT user_id,totp_secret_enc,totp_pending_secret_enc
               FROM accounts
               WHERE totp_secret_enc IS NOT NULL OR totp_pending_secret_enc IS NOT NULL"""
        ).fetchall()
        for row in rows:
            updates: dict[str, bytes | None] = {}
            for column in ("totp_secret_enc", "totp_pending_secret_enc"):
                encrypted = row[column]
                if encrypted is None:
                    updates[column] = None
                    continue
                try:
                    plaintext = old_cipher.decrypt(bytes(encrypted))
                except InvalidToken as exc:
                    raise SecurityConfigurationError(
                        "Rotazione annullata: un segreto non è decifrabile con la vecchia chiave."
                    ) from exc
                updates[column] = new_cipher.encrypt(plaintext)
            db.execute(
                """UPDATE accounts SET totp_secret_enc=?,totp_pending_secret_enc=?
                   WHERE user_id=?""",
                (updates["totp_secret_enc"], updates["totp_pending_secret_enc"], row["user_id"]),
            )
        db.commit()
        return len(rows)
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def main() -> int:
    database = os.getenv("MEDIA_AUTH_DB", "./media_data/accounts.sqlite3")
    old_key = os.getenv("MEDIA_TOTP_OLD_ENCRYPTION_KEY", "")
    new_key = os.getenv("MEDIA_TOTP_NEW_ENCRYPTION_KEY", "")
    if not old_key or not new_key:
        raise SystemExit(
            "Imposta MEDIA_TOTP_OLD_ENCRYPTION_KEY e MEDIA_TOTP_NEW_ENCRYPTION_KEY nell'ambiente protetto."
        )
    count = rotate_totp_encryption_key(database, old_key, new_key)
    print(f"Rotazione completata: {count} record TOTP cifrati aggiornati.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
