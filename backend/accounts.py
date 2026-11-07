"""Individual account primitives for the media backend.

Passwords are stored as salted scrypt hashes. Session bearer tokens are opaque,
random, stored only as SHA-256 digests, and expire/revoke server-side.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

_USERNAME = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
_ROLES = {"owner", "admin", "support", "collaborator", "user"}
_SESSION_SECONDS = 60 * 60 * 24 * 30


class AccountError(ValueError):
    """Safe account operation error."""


class AccountStore:
    def __init__(self, database: str | Path | None = None):
        configured = database or os.getenv("MEDIA_AUTH_DB", "./media_data/accounts.sqlite3")
        self.database = str(Path(configured).expanduser().resolve())
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self):
        connection = sqlite3.connect(self.database, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def _init_db(self):
        with self._connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""
                CREATE TABLE IF NOT EXISTS accounts (
                    user_id TEXT PRIMARY KEY,
                    username TEXT NOT NULL COLLATE NOCASE UNIQUE,
                    password_salt BLOB NOT NULL,
                    password_hash BLOB NOT NULL,
                    role TEXT NOT NULL CHECK(role IN
                      ('owner','admin','support','collaborator','user')),
                    created_at INTEGER NOT NULL,
                    disabled_at INTEGER
                )
            """)
            db.execute("""
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES accounts(user_id) ON DELETE CASCADE,
                    created_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    revoked_at INTEGER
                )
            """)
            db.execute("CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id)")

    @staticmethod
    def _password(password: str, salt: bytes) -> bytes:
        return hashlib.scrypt(password.encode("utf-8"), salt=salt,
                              n=2**14, r=8, p=1, dklen=32)

    @staticmethod
    def _public(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "userId": row["user_id"],
            "username": row["username"],
            "role": row["role"],
            "createdAt": row["created_at"],
        }

    def _create(self, username: str, password: str, role: str) -> dict[str, Any]:
        if not isinstance(username, str) or not _USERNAME.fullmatch(username):
            raise AccountError("Nome utente non valido: usa 3-32 caratteri alfanumerici, punto, trattino o underscore.")
        if not isinstance(password, str) or len(password) < 12 or len(password) > 1024:
            raise AccountError("La password deve contenere almeno 12 caratteri.")
        if role not in _ROLES:
            raise AccountError("Ruolo non valido.")
        salt = secrets.token_bytes(16)
        digest = self._password(password, salt)
        user_id = uuid.uuid4().hex
        now = int(time.time())
        try:
            with self._connect() as db:
                db.execute(
                    "INSERT INTO accounts(user_id,username,password_salt,password_hash,role,created_at) VALUES(?,?,?,?,?,?)",
                    (user_id, username, salt, digest, role, now),
                )
                row = db.execute("SELECT * FROM accounts WHERE user_id=?", (user_id,)).fetchone()
        except sqlite3.IntegrityError as exc:
            raise AccountError("Nome utente già utilizzato.") from exc
        return self._public(row)

    def register(self, username: str, password: str) -> dict[str, Any]:
        return self._create(username, password, "user")

    def bootstrap_owner(self, username: str, password: str) -> dict[str, Any] | None:
        """Create the first owner only; never promote an existing account."""
        with self._connect() as db:
            if db.execute("SELECT 1 FROM accounts WHERE role='owner' LIMIT 1").fetchone():
                return None
        return self._create(username, password, "owner")

    def issue_session(self, user_id: str) -> tuple[str, int]:
        now = int(time.time())
        expires = now + _SESSION_SECONDS
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        with self._connect() as db:
            row = db.execute(
                "SELECT disabled_at FROM accounts WHERE user_id=?", (user_id,)
            ).fetchone()
            if row is None or row["disabled_at"] is not None:
                raise AccountError("Account non disponibile.")
            db.execute(
                "INSERT INTO sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)",
                (token_hash, user_id, now, expires),
            )
        return token, expires

    def login(self, username: str, password: str) -> tuple[dict[str, Any], str, int]:
        with self._connect() as db:
            row = db.execute(
                "SELECT * FROM accounts WHERE username=? COLLATE NOCASE", (username,)
            ).fetchone()
        # Do a scrypt operation even for unknown usernames to reduce timing clues.
        salt = row["password_salt"] if row else b"\x00" * 16
        expected = row["password_hash"] if row else b"\x00" * 32
        actual = self._password(password if isinstance(password, str) else "", salt)
        if row is None or row["disabled_at"] is not None or not hmac.compare_digest(actual, expected):
            raise AccountError("Credenziali non valide.")
        token, expires = self.issue_session(row["user_id"])
        return self._public(row), token, expires

    def resolve_session(self, token: str | None) -> dict[str, Any] | None:
        if not isinstance(token, str) or not token or len(token) > 512:
            return None
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        now = int(time.time())
        with self._connect() as db:
            row = db.execute("""
                SELECT a.* FROM sessions s JOIN accounts a ON a.user_id=s.user_id
                WHERE s.token_hash=? AND s.revoked_at IS NULL AND s.expires_at>? AND a.disabled_at IS NULL
            """, (token_hash, now)).fetchone()
        return self._public(row) if row else None

    def revoke_session(self, token: str | None) -> bool:
        if not isinstance(token, str) or not token or len(token) > 512:
            return False
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self._connect() as db:
            cursor = db.execute(
                "UPDATE sessions SET revoked_at=? WHERE token_hash=? AND revoked_at IS NULL",
                (int(time.time()), token_hash),
            )
        return cursor.rowcount == 1
