"""Individual account primitives for the media backend.

Passwords are stored as salted scrypt hashes. Session bearer tokens are opaque,
random, stored only as SHA-256 digests, and expire/revoke server-side.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet, InvalidToken

_USERNAME = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
_ROLES = {"owner", "admin", "support", "collaborator", "user"}
_SESSION_SECONDS = 60 * 60 * 24 * 30
_OWNER_SESSION_SECONDS = 60 * 60 * 12
_TEMP_PASSWORD_SECONDS = 60 * 60 * 24


class AccountError(ValueError):
    """Safe account operation error."""


class SecurityConfigurationError(RuntimeError):
    """Required external security configuration is missing or invalid."""



def _audit_hash(previous_hash: str | None, event_id: int, actor_user_id: str | None,
                action: str, target_user_id: str | None, details_json: str,
                created_at: int, algorithm: str) -> str:
    payload = json.dumps(
        [previous_hash, event_id, actor_user_id, action, target_user_id, details_json, created_at],
        ensure_ascii=False, separators=(",", ":"),
    ).encode("utf-8")
    key = os.getenv("MEDIA_AUDIT_HMAC_KEY", "").encode("utf-8")
    if algorithm == "hmac-sha256":
        if not key:
            raise SecurityConfigurationError("MEDIA_AUDIT_HMAC_KEY is required to verify this audit chain.")
        return hmac.new(key, payload, hashlib.sha256).hexdigest()
    return hashlib.sha256(payload).hexdigest()


def _append_audit_event(db: sqlite3.Connection, actor_user_id: str | None,
                        action: str, target_user_id: str | None,
                        details: dict[str, Any] | None = None,
                        created_at: int | None = None) -> int:
    serialized = json.dumps(details or {}, ensure_ascii=False, separators=(",", ":"))
    timestamp = int(time.time()) if created_at is None else int(created_at)
    previous = db.execute(
        "SELECT event_hash FROM account_audit_events ORDER BY event_id DESC LIMIT 1"
    ).fetchone()
    previous_hash = previous["event_hash"] if previous else None
    algorithm = "hmac-sha256" if os.getenv("MEDIA_AUDIT_HMAC_KEY", "") else "sha256"
    cursor = db.execute(
        """INSERT INTO account_audit_events
           (actor_user_id,action,target_user_id,details_json,created_at,prev_hash,event_hash,hash_algorithm)
           VALUES(?,?,?,?,?,?,NULL,?)""",
        (actor_user_id, action, target_user_id, serialized, timestamp, previous_hash, algorithm),
    )
    event_id = int(cursor.lastrowid)
    digest = _audit_hash(previous_hash, event_id, actor_user_id, action,
                         target_user_id, serialized, timestamp, algorithm)
    db.execute("UPDATE account_audit_events SET event_hash=? WHERE event_id=?",
               (digest, event_id))
    return event_id


class AccountStore:
    def __init__(self, database: str | Path | None = None):
        configured = database or os.getenv("MEDIA_AUTH_DB", "./media_data/accounts.sqlite3")
        self.database = str(Path(configured).expanduser().resolve())
        Path(self.database).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._init_db()
        try:
            os.chmod(self.database, 0o600)
        except OSError:
            pass

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
            db.execute("""CREATE TABLE IF NOT EXISTS totp_replay_state (
                user_id TEXT PRIMARY KEY REFERENCES accounts(user_id) ON DELETE CASCADE,
                last_counter INTEGER NOT NULL CHECK(last_counter >= 0),
                updated_at INTEGER NOT NULL
            )""")
            db.execute("CREATE UNIQUE INDEX IF NOT EXISTS one_owner_only ON accounts(role) WHERE role='owner'")
            db.execute("""
                CREATE TABLE IF NOT EXISTS media_ownership (
                    resource_type TEXT NOT NULL CHECK(resource_type IN ('asset','job')),
                    resource_id TEXT NOT NULL,
                    owner_user_id TEXT NOT NULL REFERENCES accounts(user_id) ON DELETE CASCADE,
                    created_at INTEGER NOT NULL,
                    PRIMARY KEY(resource_type, resource_id)
                )
            """)
            db.execute("CREATE INDEX IF NOT EXISTS media_owner_idx ON media_ownership(owner_user_id, resource_type)")
            db.execute("""CREATE TABLE IF NOT EXISTS auth_rate_limits (
                key_hash TEXT PRIMARY KEY, attempts INTEGER NOT NULL,
                window_started INTEGER NOT NULL, blocked_until INTEGER NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS account_audit_events (
                event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                actor_user_id TEXT REFERENCES accounts(user_id) ON DELETE SET NULL,
                action TEXT NOT NULL,
                target_user_id TEXT REFERENCES accounts(user_id) ON DELETE SET NULL,
                details_json TEXT NOT NULL DEFAULT '{}',
                created_at INTEGER NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS account_audit_created_idx ON account_audit_events(created_at DESC)")
            db.execute("CREATE INDEX IF NOT EXISTS account_audit_actor_idx ON account_audit_events(actor_user_id, created_at DESC)")
            audit_columns = {row["name"] for row in db.execute("PRAGMA table_info(account_audit_events)").fetchall()}
            for column, declaration in (
                ("prev_hash", "TEXT"),
                ("event_hash", "TEXT"),
                ("hash_algorithm", "TEXT"),
            ):
                if column not in audit_columns:
                    db.execute(f"ALTER TABLE account_audit_events ADD COLUMN {column} {declaration}")
            # Backfill legacy audit rows once, preserving their original event order.
            if db.execute("SELECT 1 FROM account_audit_events WHERE event_hash IS NULL LIMIT 1").fetchone():
                previous_hash = None
                rows = db.execute(
                    "SELECT event_id,actor_user_id,action,target_user_id,details_json,created_at "
                    "FROM account_audit_events ORDER BY event_id"
                ).fetchall()
                algorithm = "hmac-sha256" if os.getenv("MEDIA_AUDIT_HMAC_KEY", "") else "sha256"
                for row in rows:
                    digest = _audit_hash(
                        previous_hash, row["event_id"], row["actor_user_id"], row["action"],
                        row["target_user_id"], row["details_json"], row["created_at"], algorithm,
                    )
                    db.execute(
                        "UPDATE account_audit_events SET prev_hash=?,event_hash=?,hash_algorithm=? WHERE event_id=?",
                        (previous_hash, digest, algorithm, row["event_id"]),
                    )
                    previous_hash = digest
            db.execute("""CREATE TABLE IF NOT EXISTS support_tickets (
                ticket_id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL REFERENCES accounts(user_id) ON DELETE CASCADE,
                subject TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','waiting_user','resolved','escalated')),
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS support_ticket_owner_idx ON support_tickets(owner_user_id, updated_at DESC)")
            support_columns = {row["name"] for row in db.execute("PRAGMA table_info(support_tickets)").fetchall()}
            if "assigned_to_user_id" not in support_columns:
                db.execute("ALTER TABLE support_tickets ADD COLUMN assigned_to_user_id TEXT REFERENCES accounts(user_id) ON DELETE SET NULL")
            db.execute("CREATE INDEX IF NOT EXISTS support_ticket_status_idx ON support_tickets(status, updated_at DESC)")
            db.execute("CREATE INDEX IF NOT EXISTS support_ticket_assignee_idx ON support_tickets(assigned_to_user_id, updated_at DESC)")
            db.execute("""CREATE TABLE IF NOT EXISTS support_ticket_messages (
                message_id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,
                author_user_id TEXT REFERENCES accounts(user_id) ON DELETE SET NULL,
                author_role TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS support_message_ticket_idx ON support_ticket_messages(ticket_id, created_at)")
            db.execute("""CREATE TABLE IF NOT EXISTS permission_overrides (
                user_id TEXT NOT NULL,
                permission TEXT NOT NULL,
                effect TEXT NOT NULL CHECK(effect IN ('allow','deny')),
                updated_at INTEGER NOT NULL,
                PRIMARY KEY(user_id, permission)
            )""")
            account_columns = {row["name"] for row in db.execute("PRAGMA table_info(accounts)").fetchall()}
            if "must_change_password" not in account_columns:
                db.execute("ALTER TABLE accounts ADD COLUMN must_change_password INTEGER NOT NULL DEFAULT 0")
            if "temporary_password_expires_at" not in account_columns:
                db.execute("ALTER TABLE accounts ADD COLUMN temporary_password_expires_at INTEGER")
            if "totp_secret_enc" not in account_columns:
                db.execute("ALTER TABLE accounts ADD COLUMN totp_secret_enc BLOB")
            if "totp_pending_secret_enc" not in account_columns:
                db.execute("ALTER TABLE accounts ADD COLUMN totp_pending_secret_enc BLOB")
            if "totp_enabled_at" not in account_columns:
                db.execute("ALTER TABLE accounts ADD COLUMN totp_enabled_at INTEGER")
            if "totp_pending_created_at" not in account_columns:
                db.execute("ALTER TABLE accounts ADD COLUMN totp_pending_created_at INTEGER")
            db.execute("""CREATE TABLE IF NOT EXISTS totp_recovery_codes (
                recovery_id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES accounts(user_id) ON DELETE CASCADE,
                code_hash TEXT NOT NULL UNIQUE,
                created_at INTEGER NOT NULL,
                used_at INTEGER
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS totp_recovery_user_idx ON totp_recovery_codes(user_id, used_at)")

    @staticmethod
    def _password(password: str, salt: bytes) -> bytes:
        return hashlib.scrypt(password.encode("utf-8"), salt=salt,
                              n=2**14, r=8, p=1, dklen=32)

    def _authorized_actor_role(
        self, db: sqlite3.Connection, actor_user_id: str, permission: str
    ) -> str | None:
        """Resolve an active actor and enforce the same persistent policy as HTTP routes."""
        from backend.authorization import PERMISSIONS, ROLE_DEFAULTS

        if permission not in PERMISSIONS:
            return None
        actor = db.execute(
            "SELECT role,disabled_at FROM accounts WHERE user_id=?",
            (actor_user_id,),
        ).fetchone()
        if actor is None or actor["disabled_at"] is not None:
            return None
        role = actor["role"]
        if role not in ROLE_DEFAULTS:
            return None
        if role == "owner":
            return role
        override = db.execute(
            "SELECT effect FROM permission_overrides WHERE user_id=? AND permission=?",
            (actor_user_id, permission),
        ).fetchone()
        allowed = (
            override["effect"] == "allow"
            if override is not None
            else permission in ROLE_DEFAULTS[role]
        )
        return role if allowed else None

    @staticmethod
    def _public(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "userId": row["user_id"],
            "username": row["username"],
            "role": row["role"],
            "createdAt": row["created_at"],
            "mustChangePassword": bool(row["must_change_password"]),
            "temporaryPasswordExpiresAt": row["temporary_password_expires_at"]
                if "temporary_password_expires_at" in row.keys() else None,
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

    @staticmethod
    def _rate_key(kind: str, value: str) -> str:
        return hashlib.sha256((kind + ":" + value.strip().lower()).encode("utf-8")).hexdigest()

    def login_allowed(self, ip_address: str, username: str) -> bool:
        now = int(time.time())
        keys = (self._rate_key("ip", ip_address), self._rate_key("user", username))
        with self._connect() as db:
            rows = db.execute(
                "SELECT blocked_until FROM auth_rate_limits WHERE key_hash IN (?,?)", keys
            ).fetchall()
        return not any(row["blocked_until"] > now for row in rows)

    def record_login_failure(self, ip_address: str, username: str) -> bool:
        """Record a failed factor and return True only when a throttle is newly activated."""
        now = int(time.time())
        keys = (self._rate_key("ip", ip_address), self._rate_key("user", username))
        newly_blocked = False
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            for key in keys:
                row = db.execute(
                    "SELECT attempts,window_started,blocked_until FROM auth_rate_limits WHERE key_hash=?", (key,)
                ).fetchone()
                if row is None or now - row["window_started"] >= 900:
                    attempts, started = 1, now
                else:
                    attempts, started = row["attempts"] + 1, row["window_started"]
                if attempts >= 10 and (row is None or row["blocked_until"] <= now):
                    newly_blocked = True
                blocked = now + 900 if attempts >= 10 else 0
                db.execute("""
                    INSERT INTO auth_rate_limits(key_hash,attempts,window_started,blocked_until)
                    VALUES(?,?,?,?) ON CONFLICT(key_hash) DO UPDATE SET
                    attempts=excluded.attempts,window_started=excluded.window_started,
                    blocked_until=excluded.blocked_until
                """, (key, attempts, started, blocked))
        return newly_blocked

    def record_login_success(
        self, user_id: str, role: str, ip_address: str
    ) -> bool:
        """Audit a new session with a one-way IP fingerprint; return whether IP is new."""
        ip_hash = self._rate_key("ip", ip_address)
        with self._connect() as db:
            rows = db.execute(
                """SELECT details_json FROM account_audit_events
                   WHERE actor_user_id=? AND action='auth.login_success'
                   ORDER BY event_id DESC LIMIT 100""",
                (user_id,),
            ).fetchall()
        seen = False
        for row in rows:
            try:
                if json.loads(row["details_json"]).get("ipHash") == ip_hash:
                    seen = True
                    break
            except (TypeError, ValueError):
                continue
        new_ip = not seen
        self.record_audit_event(
            user_id, "auth.login_success", user_id,
            {"role": role, "ipHash": ip_hash, "newIp": new_ip},
        )
        return new_ip

    def clear_login_failures(self, ip_address: str, username: str) -> None:
        keys = (self._rate_key("ip", ip_address), self._rate_key("user", username))
        with self._connect() as db:
            db.executemany("DELETE FROM auth_rate_limits WHERE key_hash=?", [(key,) for key in keys])

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
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        with self._connect() as db:
            row = db.execute(
                "SELECT role,disabled_at FROM accounts WHERE user_id=?", (user_id,)
            ).fetchone()
            if row is None or row["disabled_at"] is not None:
                raise AccountError("Account non disponibile.")
            lifetime = _OWNER_SESSION_SECONDS if row["role"] == "owner" else _SESSION_SECONDS
            expires = now + lifetime
            db.execute(
                "INSERT INTO sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)",
                (token_hash, user_id, now, expires),
            )
        return token, expires

    def authenticate_password(self, username: str, password: str) -> dict[str, Any]:
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
        if (
            row["must_change_password"]
            and row["temporary_password_expires_at"] is not None
            and row["temporary_password_expires_at"] <= int(time.time())
        ):
            raise AccountError("Password temporanea scaduta. Richiedi un nuovo reset all'assistenza.")
        return self._public(row)

    def login(
        self, username: str, password: str, totp_code: str | None = None
    ) -> tuple[dict[str, Any], str, int]:
        account = self.authenticate_password(username, password)
        if account["role"] == "owner" and self.totp_enabled(account["userId"]):
            if not isinstance(totp_code, str) or not self.verify_owner_second_factor(
                account["userId"], totp_code
            ):
                raise AccountError("Secondo fattore non valido o richiesto.")
        token, expires = self.issue_session(account["userId"])
        return account, token, expires

    @staticmethod
    def _totp_fernet() -> Fernet:
        configured = os.getenv("MEDIA_TOTP_ENCRYPTION_KEY", "").strip()
        if not configured:
            raise SecurityConfigurationError(
                "MEDIA_TOTP_ENCRYPTION_KEY non configurata: autenticazione 2FA bloccata."
            )
        try:
            return Fernet(configured.encode("ascii"))
        except (ValueError, UnicodeEncodeError) as exc:
            raise SecurityConfigurationError(
                "MEDIA_TOTP_ENCRYPTION_KEY non valida: autenticazione 2FA bloccata."
            ) from exc

    @staticmethod
    def _recovery_hash(code: str) -> str:
        return hashlib.sha256(code.strip().upper().encode("utf-8")).hexdigest()

    def totp_enabled(self, user_id: str) -> bool:
        with self._connect() as db:
            row = db.execute(
                "SELECT role,totp_enabled_at,totp_secret_enc FROM accounts WHERE user_id=?",
                (user_id,),
            ).fetchone()
        return bool(
            row and row["role"] == "owner" and row["totp_enabled_at"] is not None
            and row["totp_secret_enc"]
        )

    def begin_totp_setup(self, user_id: str, password: str) -> str:
        fernet = self._totp_fernet()
        with self._connect() as db:
            row = db.execute(
                "SELECT role,password_salt,password_hash,disabled_at FROM accounts WHERE user_id=?",
                (user_id,),
            ).fetchone()
        if row is None or row["role"] != "owner" or row["disabled_at"] is not None:
            raise AccountError("Operazione riservata al proprietario.")
        actual = self._password(password if isinstance(password, str) else "", row["password_salt"])
        if not hmac.compare_digest(actual, row["password_hash"]):
            raise AccountError("Password non valida.")
        if self.totp_enabled(user_id):
            raise AccountError("La verifica in due passaggi è già attiva.")
        from backend.totp import generate_secret
        secret = generate_secret()
        encrypted = fernet.encrypt(secret.encode("ascii"))
        with self._connect() as db:
            db.execute(
                "UPDATE accounts SET totp_pending_secret_enc=?,totp_pending_created_at=? WHERE user_id=? AND role='owner'",
                (encrypted, int(time.time()), user_id),
            )
        return secret

    def confirm_totp_setup(self, user_id: str, code: str) -> list[str]:
        from backend.totp import matching_counter
        with self._connect() as db:
            row = db.execute(
                "SELECT role,totp_pending_secret_enc,totp_pending_created_at,disabled_at FROM accounts WHERE user_id=?",
                (user_id,),
            ).fetchone()
        if row is None or row["role"] != "owner" or row["disabled_at"] is not None:
            raise AccountError("Operazione riservata al proprietario.")
        if not row["totp_pending_secret_enc"]:
            raise AccountError("Avvia prima la configurazione della verifica in due passaggi.")
        if (row["totp_pending_created_at"] is None
                or int(time.time()) - row["totp_pending_created_at"] > 600):
            with self._connect() as db:
                db.execute(
                    "UPDATE accounts SET totp_pending_secret_enc=NULL,totp_pending_created_at=NULL WHERE user_id=?",
                    (user_id,),
                )
            raise AccountError("Configurazione 2FA scaduta; avvia nuovamente la procedura.")
        try:
            secret = self._totp_fernet().decrypt(row["totp_pending_secret_enc"]).decode("ascii")
        except InvalidToken as exc:
            raise SecurityConfigurationError("Segreto 2FA non decifrabile.") from exc
        counter = matching_counter(secret, code, window=1)
        if counter is None:
            raise AccountError("Codice di verifica non valido.")
        recovery_codes = [secrets.token_hex(16).upper() for _ in range(10)]
        now = int(time.time())
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            current = db.execute(
                "SELECT totp_pending_secret_enc,totp_enabled_at FROM accounts WHERE user_id=? AND role='owner'",
                (user_id,),
            ).fetchone()
            if current is None or current["totp_enabled_at"] is not None or not hmac.compare_digest(
                bytes(current["totp_pending_secret_enc"] or b""), bytes(row["totp_pending_secret_enc"])
            ):
                raise AccountError("Configurazione 2FA modificata; ripeti la procedura.")
            db.execute(
                """UPDATE accounts SET totp_secret_enc=?,totp_pending_secret_enc=NULL,
                   totp_pending_created_at=NULL,totp_enabled_at=? WHERE user_id=?""",
                (row["totp_pending_secret_enc"], now, user_id),
            )
            db.execute(
                """INSERT INTO totp_replay_state(user_id,last_counter,updated_at) VALUES(?,?,?)
                   ON CONFLICT(user_id) DO UPDATE SET last_counter=excluded.last_counter,
                   updated_at=excluded.updated_at""",
                (user_id, counter, now),
            )
            # Force every previously issued owner session to reauthenticate with 2FA.
            db.execute(
                "UPDATE sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                (now, user_id),
            )
            db.execute("DELETE FROM totp_recovery_codes WHERE user_id=?", (user_id,))
            db.executemany(
                """INSERT INTO totp_recovery_codes(user_id,code_hash,created_at)
                   VALUES(?,?,?)""",
                [(user_id, self._recovery_hash(item), now) for item in recovery_codes],
            )
        self.record_audit_event(user_id, "security.totp_enabled", user_id, {"recovery_codes": len(recovery_codes)})
        return recovery_codes

    def verify_owner_second_factor(self, user_id: str, supplied: str) -> bool:
        from backend.totp import matching_counter
        if not isinstance(supplied, str) or not 6 <= len(supplied) <= 64:
            return False
        with self._connect() as db:
            row = db.execute(
                """SELECT role,totp_secret_enc,totp_enabled_at,disabled_at
                   FROM accounts WHERE user_id=?""",
                (user_id,),
            ).fetchone()
        if (row is None or row["role"] != "owner" or row["disabled_at"] is not None
                or row["totp_enabled_at"] is None or not row["totp_secret_enc"]):
            return False
        try:
            secret = self._totp_fernet().decrypt(row["totp_secret_enc"]).decode("ascii")
        except InvalidToken as exc:
            raise SecurityConfigurationError("Segreto 2FA non decifrabile.") from exc
        counter = matching_counter(secret, supplied, window=1)
        if counter is not None and self.consume_totp_counter(user_id, counter):
            return True
        # Recovery codes are random, high-entropy, one-time values stored only as hashes.
        code_hash = self._recovery_hash(supplied)
        now = int(time.time())
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            result = db.execute(
                """UPDATE totp_recovery_codes SET used_at=?
                   WHERE user_id=? AND code_hash=? AND used_at IS NULL""",
                (now, user_id, code_hash),
            )
            return result.rowcount == 1

    def disable_totp(self, user_id: str, password: str, code: str) -> None:
        with self._connect() as db:
            row = db.execute(
                "SELECT role,password_salt,password_hash,disabled_at FROM accounts WHERE user_id=?",
                (user_id,),
            ).fetchone()
        if row is None or row["role"] != "owner" or row["disabled_at"] is not None:
            raise AccountError("Operazione riservata al proprietario.")
        actual = self._password(password if isinstance(password, str) else "", row["password_salt"])
        if not hmac.compare_digest(actual, row["password_hash"]):
            raise AccountError("Password non valida.")
        if not self.verify_owner_second_factor(user_id, code):
            raise AccountError("Secondo fattore non valido.")
        now = int(time.time())
        with self._connect() as db:
            db.execute(
                """UPDATE accounts SET totp_secret_enc=NULL,totp_pending_secret_enc=NULL,
                   totp_pending_created_at=NULL,totp_enabled_at=NULL WHERE user_id=?""",
                (user_id,),
            )
            db.execute("DELETE FROM totp_recovery_codes WHERE user_id=?", (user_id,))
            db.execute("DELETE FROM totp_replay_state WHERE user_id=?", (user_id,))
            db.execute(
                "UPDATE sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                (now, user_id),
            )
        self.record_audit_event(user_id, "security.totp_disabled", user_id, {})

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

    def list_active_sessions(
        self, user_id: str, limit: int = 50
    ) -> list[dict[str, Any]]:
        """List only non-revoked, unexpired sessions; token hashes are identifiers, not credentials."""
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            return []
        if not isinstance(limit, int) or isinstance(limit, bool):
            limit = 50
        limit = max(1, min(100, limit))
        now = int(time.time())
        with self._connect() as db:
            rows = db.execute(
                """SELECT s.token_hash,s.created_at,s.expires_at
                   FROM sessions s JOIN accounts a ON a.user_id=s.user_id
                   WHERE s.user_id=? AND s.revoked_at IS NULL AND s.expires_at>?
                     AND a.disabled_at IS NULL
                   ORDER BY s.created_at DESC LIMIT ?""",
                (user_id, now, limit),
            ).fetchall()
        return [{
            "sessionId": row["token_hash"],
            "createdAt": row["created_at"],
            "expiresAt": row["expires_at"],
        } for row in rows]

    def revoke_session_by_id(self, user_id: str, session_id: str) -> bool:
        if (not isinstance(user_id, str) or not user_id or len(user_id) > 128
                or not isinstance(session_id, str)
                or not re.fullmatch(r"[0-9a-f]{64}", session_id)):
            return False
        with self._connect() as db:
            result = db.execute(
                """UPDATE sessions SET revoked_at=?
                   WHERE token_hash=? AND user_id=? AND revoked_at IS NULL AND expires_at>?""",
                (int(time.time()), session_id, user_id, int(time.time())),
            )
        return result.rowcount == 1

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

    def consume_totp_counter(self, user_id: str, counter: int) -> bool:
        """Atomically accept a TOTP counter only once and only in increasing order.

        Call this only after cryptographically verifying the submitted TOTP code.
        BEGIN IMMEDIATE serializes competing requests so parallel replays cannot
        both consume the same moving counter.
        """
        if (not isinstance(user_id, str) or not user_id or len(user_id) > 128
                or not isinstance(counter, int) or isinstance(counter, bool)
                or counter < 0):
            return False
        now = int(time.time())
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            account = db.execute(
                "SELECT disabled_at FROM accounts WHERE user_id=?", (user_id,)
            ).fetchone()
            if account is None or account["disabled_at"] is not None:
                return False
            previous = db.execute(
                "SELECT last_counter FROM totp_replay_state WHERE user_id=?",
                (user_id,),
            ).fetchone()
            if previous is not None and counter <= previous["last_counter"]:
                return False
            if previous is None:
                db.execute(
                    "INSERT INTO totp_replay_state(user_id,last_counter,updated_at) VALUES(?,?,?)",
                    (user_id, counter, now),
                )
            else:
                updated = db.execute(
                    """UPDATE totp_replay_state SET last_counter=?,updated_at=?
                       WHERE user_id=? AND last_counter<?""",
                    (counter, now, user_id, counter),
                )
                if updated.rowcount != 1:
                    return False
            return True

    def claim_media_resource(self, resource_type: str, resource_id: str, owner_user_id: str) -> None:
        """Bind a server-generated asset/job identifier to one account exactly once."""
        if resource_type not in {"asset", "job"}:
            raise AccountError("Tipo di risorsa non valido.")
        if not isinstance(resource_id, str) or not re.fullmatch(r"[0-9a-f]{32}", resource_id):
            raise AccountError("Identificativo risorsa non valido.")
        now = int(time.time())
        try:
            with self._connect() as db:
                account = db.execute(
                    "SELECT 1 FROM accounts WHERE user_id=? AND disabled_at IS NULL",
                    (owner_user_id,),
                ).fetchone()
                if account is None:
                    raise AccountError("Account non disponibile.")
                db.execute(
                    "INSERT INTO media_ownership(resource_type,resource_id,owner_user_id,created_at) VALUES(?,?,?,?)",
                    (resource_type, resource_id, owner_user_id, now),
                )
        except sqlite3.IntegrityError as exc:
            raise AccountError("Risorsa già associata a un account.") from exc

    def release_media_resource(
        self, resource_type: str, resource_id: str, owner_user_id: str
    ) -> bool:
        """Release a resource claim only for the account that owns it."""
        if resource_type not in {"asset", "job"}:
            return False
        if (not isinstance(resource_id, str)
                or not re.fullmatch(r"[0-9a-f]{32}", resource_id)
                or not isinstance(owner_user_id, str)
                or not owner_user_id or len(owner_user_id) > 128):
            return False
        with self._connect() as db:
            result = db.execute(
                "DELETE FROM media_ownership WHERE resource_type=? AND resource_id=? AND owner_user_id=?",
                (resource_type, resource_id, owner_user_id),
            )
        return result.rowcount == 1

    def owns_media_resource(self, resource_type: str, resource_id: str, owner_user_id: str) -> bool:
        if resource_type not in {"asset", "job"}:
            return False
        with self._connect() as db:
            row = db.execute(
                "SELECT 1 FROM media_ownership WHERE resource_type=? AND resource_id=? AND owner_user_id=?",
                (resource_type, resource_id, owner_user_id),
            ).fetchone()
        return row is not None

    def get_media_resource_owner(self, resource_type: str, resource_id: str) -> str | None:
        if resource_type not in {"asset", "job"}:
            return None
        with self._connect() as db:
            row = db.execute(
                "SELECT owner_user_id FROM media_ownership WHERE resource_type=? AND resource_id=?",
                (resource_type, resource_id),
            ).fetchone()
        return row["owner_user_id"] if row else None

    def get_account(self, user_id: str) -> dict[str, Any] | None:
        """Return one account's public fields without credential material."""
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            return None
        with self._connect() as db:
            row = db.execute(
                """SELECT user_id,username,role,created_at,disabled_at
                   FROM accounts WHERE user_id=?""",
                (user_id,),
            ).fetchone()
        if row is None:
            return None
        return {
            "userId": row["user_id"],
            "username": row["username"],
            "role": row["role"],
            "createdAt": row["created_at"],
            "disabled": row["disabled_at"] is not None,
        }

    def list_accounts(
        self, limit: int = 100, search: str | None = None
    ) -> list[dict[str, Any]]:
        """Return public account fields only; never expose password hashes or sessions."""
        if not isinstance(limit, int) or isinstance(limit, bool):
            limit = 100
        limit = max(1, min(200, limit))
        term = search.strip()[:64] if isinstance(search, str) else ""
        with self._connect() as db:
            if term:
                escaped = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
                rows = db.execute(
                    """SELECT user_id,username,role,created_at,disabled_at
                       FROM accounts
                       WHERE username LIKE ? ESCAPE '\\' COLLATE NOCASE
                          OR user_id LIKE ? ESCAPE '\\'
                       ORDER BY created_at DESC,user_id LIMIT ?""",
                    (f"%{escaped}%", f"%{escaped}%", limit),
                ).fetchall()
            else:
                rows = db.execute(
                    """SELECT user_id,username,role,created_at,disabled_at
                       FROM accounts ORDER BY created_at DESC,user_id LIMIT ?""",
                    (limit,),
                ).fetchall()
        return [{
            "userId": row["user_id"],
            "username": row["username"],
            "role": row["role"],
            "createdAt": row["created_at"],
            "disabled": row["disabled_at"] is not None,
        } for row in rows]

    def admin_dashboard_stats(self) -> dict[str, Any]:
        """Return aggregate operational counters only; never expose account identities."""
        now = int(time.time())
        with self._connect() as db:
            total = db.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            active = db.execute(
                "SELECT COUNT(*) FROM accounts WHERE disabled_at IS NULL"
            ).fetchone()[0]
            disabled = db.execute(
                "SELECT COUNT(*) FROM accounts WHERE disabled_at IS NOT NULL"
            ).fetchone()[0]
            rows = db.execute(
                "SELECT role,COUNT(*) AS count FROM accounts GROUP BY role"
            ).fetchall()
            recent = db.execute(
                "SELECT COUNT(*) FROM accounts WHERE created_at>=?",
                (now - 30 * 86400,),
            ).fetchone()[0]
        return {
            "totalAccounts": int(total),
            "activeAccounts": int(active),
            "disabledAccounts": int(disabled),
            "createdLast30Days": int(recent),
            "accountsByRole": {row["role"]: int(row["count"]) for row in rows},
        }

    def create_managed_account(
        self, actor_user_id: str, username: str, password: str, role: str
    ) -> dict[str, Any]:
        """Allow the owner to create non-owner accounts; never create another owner."""
        if role == "owner":
            raise AccountError("L'account proprietario non può essere creato tramite gestione account.")
        if role not in {"admin", "support", "collaborator", "user"}:
            raise AccountError("Ruolo non valido o riservato.")
        if not isinstance(username, str) or not _USERNAME.fullmatch(username):
            raise AccountError("Nome utente non valido: usa 3-32 caratteri alfanumerici, punto, trattino o underscore.")
        if not isinstance(password, str) or len(password) < 12 or len(password) > 1024:
            raise AccountError("La password deve contenere almeno 12 caratteri.")
        salt = secrets.token_bytes(16)
        digest = self._password(password, salt)
        user_id = uuid.uuid4().hex
        now = int(time.time())
        try:
            with self._connect() as db:
                actor_role = self._authorized_actor_role(db, actor_user_id, "accounts.create")
                if actor_role is None:
                    raise AccountError("Permesso di creazione account insufficiente.")
                if actor_role != "owner" and role not in {"user", "collaborator"}:
                    raise AccountError("Solo il proprietario può creare account admin o support.")
                db.execute(
                    """INSERT INTO accounts
                       (user_id,username,password_salt,password_hash,role,created_at,
                        must_change_password,temporary_password_expires_at)
                       VALUES(?,?,?,?,?,?,1,?)""",
                    (user_id, username, salt, digest, role, now,
                     now + _TEMP_PASSWORD_SECONDS),
                )
                _append_audit_event(db, actor_user_id, "account.created", user_id, {"role": role}, now)
                row = db.execute(
                    """SELECT user_id,username,role,created_at,must_change_password,
                              temporary_password_expires_at FROM accounts WHERE user_id=?""",
                    (user_id,),
                ).fetchone()
        except sqlite3.IntegrityError as exc:
            raise AccountError("Nome utente già utilizzato.") from exc
        return self._public(row)


    def reset_account_password(self, actor_user_id: str, target_user_id: str) -> str:
        """Issue a high-entropy one-time temporary password, returned only once."""
        temporary = secrets.token_urlsafe(24)
        salt = secrets.token_bytes(16)
        digest = self._password(temporary, salt)
        now = int(time.time())
        with self._connect() as db:
            actor_role = self._authorized_actor_role(db, actor_user_id, "accounts.password_reset")
            if actor_role is None:
                raise AccountError("Permesso di reset password insufficiente.")
            target = db.execute(
                "SELECT role FROM accounts WHERE user_id=?", (target_user_id,)
            ).fetchone()
            if target is None:
                raise AccountError("Account non trovato.")
            if target["role"] == "owner":
                raise AccountError("Il reset dell'account proprietario richiede la procedura dedicata.")
            if actor_role != "owner" and target["role"] == "admin":
                raise AccountError("Solo il proprietario può reimpostare le credenziali di un amministratore.")
            db.execute(
                """UPDATE accounts
                   SET password_salt=?,password_hash=?,must_change_password=1,
                       temporary_password_expires_at=?
                   WHERE user_id=?""",
                (salt, digest, now + _TEMP_PASSWORD_SECONDS, target_user_id),
            )
            db.execute(
                "UPDATE sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                (now, target_user_id),
            )
            _append_audit_event(db, actor_user_id, "account.password_reset", target_user_id, {}, now)
        return temporary

    def change_password(
        self, user_id: str, current_password: str | None, new_password: str
    ) -> None:
        if not isinstance(new_password, str) or len(new_password) < 12 or len(new_password) > 1024:
            raise AccountError("La nuova password deve contenere almeno 12 caratteri.")
        salt = secrets.token_bytes(16)
        digest = self._password(new_password, salt)
        now = int(time.time())
        with self._connect() as db:
            row = db.execute(
                """SELECT password_salt,password_hash,must_change_password,
                          temporary_password_expires_at,disabled_at
                   FROM accounts WHERE user_id=?""",
                (user_id,),
            ).fetchone()
            if row is None or row["disabled_at"] is not None:
                raise AccountError("Account non disponibile.")
            if (
                row["must_change_password"]
                and row["temporary_password_expires_at"] is not None
                and row["temporary_password_expires_at"] <= now
            ):
                raise AccountError("Password temporanea scaduta. Richiedi un nuovo reset all'assistenza.")
            if not row["must_change_password"]:
                actual = self._password(current_password or "", row["password_salt"])
                if not hmac.compare_digest(actual, row["password_hash"]):
                    raise AccountError("Password attuale non valida.")
            db.execute(
                """UPDATE accounts SET password_salt=?,password_hash=?,
                       must_change_password=0,temporary_password_expires_at=NULL
                   WHERE user_id=?""",
                (salt, digest, user_id),
            )
            db.execute(
                "UPDATE sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                (now, user_id),
            )
            _append_audit_event(db, user_id, "account.password_changed", user_id, {}, now)

    def set_account_role(
        self, actor_user_id: str, target_user_id: str, role: str
    ) -> dict[str, Any]:
        """Owner-only role changes; protect owner and revoke stale privilege sessions."""
        if role not in {"admin", "support", "collaborator", "user"}:
            raise AccountError("Ruolo non valido o riservato.")
        now = int(time.time())
        with self._connect() as db:
            actor_role = self._authorized_actor_role(db, actor_user_id, "accounts.update")
            if actor_role is None:
                raise AccountError("Permesso di modifica ruolo insufficiente.")
            target = db.execute(
                "SELECT user_id,username,role,created_at,disabled_at FROM accounts WHERE user_id=?",
                (target_user_id,),
            ).fetchone()
            if target is None:
                raise AccountError("Account non trovato.")
            if target["role"] == "owner":
                raise AccountError("Il ruolo proprietario non può essere modificato.")
            if actor_role != "owner" and (target["role"] == "admin" or role == "admin"):
                raise AccountError("Solo il proprietario può modificare o assegnare il ruolo admin.")
            db.execute("UPDATE accounts SET role=? WHERE user_id=?", (role, target_user_id))
            # Existing sessions carry a stale role snapshot; require a fresh login.
            db.execute(
                "UPDATE sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                (now, target_user_id),
            )
            _append_audit_event(db, actor_user_id, "account.role_changed", target_user_id, {"role": role}, now)
            return {
                "userId": target["user_id"],
                "username": target["username"],
                "role": role,
                "createdAt": target["created_at"],
                "disabled": target["disabled_at"] is not None,
            }

    def set_account_disabled(
        self, actor_user_id: str, target_user_id: str, disabled: bool
    ) -> dict[str, Any]:
        """Owner-only account suspension/reactivation; owner account is immutable."""
        if not isinstance(disabled, bool):
            raise AccountError("Stato account non valido.")
        now = int(time.time())
        with self._connect() as db:
            actor_role = self._authorized_actor_role(db, actor_user_id, "accounts.disable")
            if actor_role is None:
                raise AccountError("Permesso di sospensione account insufficiente.")
            target = db.execute(
                "SELECT user_id,username,role,created_at,disabled_at FROM accounts WHERE user_id=?",
                (target_user_id,),
            ).fetchone()
            if target is None:
                raise AccountError("Account non trovato.")
            if target["role"] == "owner":
                raise AccountError("L'account proprietario non può essere sospeso o modificato.")
            if actor_role != "owner" and target["role"] == "admin":
                raise AccountError("Solo il proprietario può sospendere un amministratore.")
            disabled_at = now if disabled else None
            db.execute(
                "UPDATE accounts SET disabled_at=? WHERE user_id=?",
                (disabled_at, target_user_id),
            )
            if disabled:
                db.execute(
                    "UPDATE sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                    (now, target_user_id),
                )
            action = "account.disabled" if disabled else "account.enabled"
            _append_audit_event(db, actor_user_id, action, target_user_id, {}, now)
            return {
                "userId": target["user_id"],
                "username": target["username"],
                "role": target["role"],
                "createdAt": target["created_at"],
                "disabled": disabled,
            }

    def create_support_ticket(self, owner_user_id: str, subject: str, message: str) -> dict[str, Any]:
        subject = subject.strip() if isinstance(subject, str) else ""
        message = message.strip() if isinstance(message, str) else ""
        if not 5 <= len(subject) <= 120:
            raise AccountError("L'oggetto del ticket deve contenere da 5 a 120 caratteri.")
        if not 10 <= len(message) <= 4000:
            raise AccountError("Il messaggio deve contenere da 10 a 4000 caratteri.")
        ticket_id, message_id, now = uuid.uuid4().hex, uuid.uuid4().hex, int(time.time())
        with self._connect() as db:
            account = db.execute("SELECT role,disabled_at FROM accounts WHERE user_id=?", (owner_user_id,)).fetchone()
            if account is None or account["disabled_at"] is not None:
                raise AccountError("Account non disponibile.")
            db.execute("INSERT INTO support_tickets(ticket_id,owner_user_id,subject,status,created_at,updated_at) VALUES(?,?,?,'open',?,?)", (ticket_id, owner_user_id, subject, now, now))
            db.execute("INSERT INTO support_ticket_messages VALUES(?,?,?,?,?,?)",
                       (message_id, ticket_id, owner_user_id, account["role"], message, now))
        self.record_audit_event(owner_user_id, "support.ticket_created", owner_user_id, {"ticketId": ticket_id})
        return self.get_support_ticket(ticket_id)

    def assign_support_ticket(self, ticket_id: str, actor_user_id: str, assignee_user_id: str | None) -> dict[str, Any]:
        """Assign a ticket to an active Support account, or clear its assignment."""
        with self._connect() as db:
            ticket = db.execute("SELECT ticket_id FROM support_tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
            if ticket is None:
                raise AccountError("Ticket non trovato.")
            if assignee_user_id is not None:
                assignee = db.execute(
                    "SELECT role,disabled_at FROM accounts WHERE user_id=?", (assignee_user_id,)
                ).fetchone()
                if assignee is None or assignee["disabled_at"] is not None or assignee["role"] != "support":
                    raise AccountError("Assegnatario non valido: seleziona un account Assistenza attivo.")
            db.execute(
                "UPDATE support_tickets SET assigned_to_user_id=?,updated_at=? WHERE ticket_id=?",
                (assignee_user_id, int(time.time()), ticket_id),
            )
        self.record_audit_event(
            actor_user_id, "support.ticket_assigned", None,
            {"ticketId": ticket_id, "assigneeUserId": assignee_user_id},
        )
        updated = self.get_support_ticket(ticket_id)
        if updated is None:
            raise AccountError("Ticket non trovato.")
        return updated

    def list_support_tickets(self, owner_user_id: str | None = None, status: str | None = None,
                             limit: int = 50, offset: int = 0) -> list[dict[str, Any]]:
        limit = max(1, min(100, limit if isinstance(limit, int) and not isinstance(limit, bool) else 50))
        offset = max(0, min(1_000_000, offset if isinstance(offset, int) and not isinstance(offset, bool) else 0))
        clauses, values = [], []
        if owner_user_id:
            clauses.append("owner_user_id=?"); values.append(owner_user_id)
        if status:
            if status not in {"open", "waiting_user", "resolved", "escalated"}:
                raise AccountError("Stato ticket non valido.")
            clauses.append("status=?"); values.append(status)
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        values.extend((limit, offset))
        with self._connect() as db:
            rows = db.execute("""SELECT ticket_id,owner_user_id,assigned_to_user_id,subject,status,created_at,updated_at
                FROM support_tickets""" + where + " ORDER BY updated_at DESC,ticket_id LIMIT ? OFFSET ?", values).fetchall()
        return [{"ticketId": r["ticket_id"], "ownerUserId": r["owner_user_id"],
                 "assignedToUserId": r["assigned_to_user_id"], "subject": r["subject"],
                 "status": r["status"], "createdAt": r["created_at"], "updatedAt": r["updated_at"]} for r in rows]

    def get_support_ticket(self, ticket_id: str) -> dict[str, Any] | None:
        if not isinstance(ticket_id, str) or not re.fullmatch(r"[a-f0-9]{32}", ticket_id):
            return None
        with self._connect() as db:
            ticket = db.execute("SELECT * FROM support_tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
            if ticket is None: return None
            messages = db.execute("""SELECT message_id,author_user_id,author_role,body,created_at
                FROM support_ticket_messages WHERE ticket_id=? ORDER BY created_at,message_id""", (ticket_id,)).fetchall()
        return {"ticketId": ticket["ticket_id"], "ownerUserId": ticket["owner_user_id"],
                "assignedToUserId": ticket["assigned_to_user_id"],
                "subject": ticket["subject"], "status": ticket["status"],
                "createdAt": ticket["created_at"], "updatedAt": ticket["updated_at"],
                "messages": [{"messageId": m["message_id"], "authorUserId": m["author_user_id"],
                              "authorRole": m["author_role"], "body": m["body"], "createdAt": m["created_at"]}
                             for m in messages]}

    def reply_support_ticket(self, ticket_id: str, actor_user_id: str, body: str,
                              actor_role: str, status: str | None = None) -> dict[str, Any]:
        body = body.strip() if isinstance(body, str) else ""
        if not 1 <= len(body) <= 4000: raise AccountError("La risposta deve contenere da 1 a 4000 caratteri.")
        if status is not None and status not in {"open", "waiting_user", "resolved", "escalated"}:
            raise AccountError("Stato ticket non valido.")
        now, message_id = int(time.time()), uuid.uuid4().hex
        with self._connect() as db:
            ticket = db.execute("SELECT owner_user_id,status FROM support_tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
            if ticket is None: raise AccountError("Ticket non trovato.")
            if actor_role not in {"owner", "admin", "support"} and ticket["owner_user_id"] != actor_user_id:
                raise AccountError("Ticket non disponibile.")
            if actor_role in {"owner", "admin", "support"}:
                new_status = status or ("resolved" if ticket["status"] == "resolved" else "waiting_user")
            else:
                if status is not None: raise AccountError("Solo l'assistenza può modificare lo stato del ticket.")
                new_status = "open"
            db.execute("INSERT INTO support_ticket_messages VALUES(?,?,?,?,?,?)",
                       (message_id, ticket_id, actor_user_id, actor_role, body, now))
            db.execute("UPDATE support_tickets SET status=?,updated_at=? WHERE ticket_id=?", (new_status, now, ticket_id))
        self.record_audit_event(actor_user_id, "support.ticket_replied", ticket["owner_user_id"],
                                {"ticketId": ticket_id, "status": new_status})
        return self.get_support_ticket(ticket_id)

    def record_audit_event(
        self,
        actor_user_id: str | None,
        action: str,
        target_user_id: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> int:
        """Persist a minimal account-security event; never accept secrets in details."""
        if not isinstance(action, str) or not re.fullmatch(r"[a-z][a-z0-9_.-]{1,63}", action):
            raise AccountError("Azione audit non valida.")
        if details is None:
            details = {}
        if not isinstance(details, dict) or len(details) > 20:
            raise AccountError("Dettagli audit non validi.")
        forbidden = {
            "password", "token", "secret", "authorization", "credential",
            "apikey", "otp", "privatekey", "cookie", "bearer", "session",
        }
        for key, value in details.items():
            normalized_key = re.sub(r"[^a-z0-9]", "", key.lower()) if isinstance(key, str) else ""
            if not normalized_key or any(secret_name in normalized_key for secret_name in forbidden):
                raise AccountError("I dettagli audit non possono contenere credenziali o segreti.")
            if not isinstance(value, (str, int, float, bool, type(None))):
                raise AccountError("I dettagli audit devono essere valori semplici.")
        serialized = json.dumps(details, ensure_ascii=False, separators=(",", ":"))
        if len(serialized.encode("utf-8")) > 4096:
            raise AccountError("Dettagli audit troppo grandi.")
        with self._connect() as db:
            # Acquire the SQLite write reservation before reading the previous hash.
            # Without this, simultaneous audit writers could read the same chain tail
            # and either contend on a stale snapshot or append against the wrong tail.
            db.execute("BEGIN IMMEDIATE")
            return _append_audit_event(db, actor_user_id, action, target_user_id, details, int(time.time()))

    def verify_audit_chain(self) -> dict[str, Any]:
        """Verify the persisted audit hash chain; HMAC mode requires the same server key."""
        with self._connect() as db:
            rows = db.execute(
                """SELECT event_id,actor_user_id,action,target_user_id,details_json,
                          created_at,prev_hash,event_hash,hash_algorithm
                   FROM account_audit_events ORDER BY event_id"""
            ).fetchall()
        previous_hash = None
        algorithm = None
        for row in rows:
            current_algorithm = row["hash_algorithm"]
            if current_algorithm not in {"sha256", "hmac-sha256"}:
                return {"valid": False, "count": len(rows),
                        "firstInvalidEventId": row["event_id"], "algorithm": current_algorithm}
            if algorithm is not None and current_algorithm != algorithm:
                return {"valid": False, "count": len(rows),
                        "firstInvalidEventId": row["event_id"], "algorithm": "mixed"}
            algorithm = current_algorithm
            if row["prev_hash"] != previous_hash:
                return {"valid": False, "count": len(rows),
                        "firstInvalidEventId": row["event_id"], "algorithm": algorithm}
            try:
                expected = _audit_hash(
                    previous_hash, row["event_id"], row["actor_user_id"], row["action"],
                    row["target_user_id"], row["details_json"], row["created_at"], algorithm,
                )
            except SecurityConfigurationError:
                return {"valid": False, "count": len(rows),
                        "firstInvalidEventId": row["event_id"], "algorithm": algorithm,
                        "keyAvailable": False}
            if not hmac.compare_digest(expected, row["event_hash"] or ""):
                return {"valid": False, "count": len(rows),
                        "firstInvalidEventId": row["event_id"], "algorithm": algorithm}
            previous_hash = row["event_hash"]
        return {"valid": True, "count": len(rows), "firstInvalidEventId": None,
                "algorithm": algorithm or "sha256",
                "keyAvailable": algorithm != "hmac-sha256" or bool(os.getenv("MEDIA_AUDIT_HMAC_KEY", ""))}

    def list_audit_events(
        self,
        limit: int = 50,
        offset: int = 0,
        action: str | None = None,
        actor_user_id: str | None = None,
        target_user_id: str | None = None,
        since: int | None = None,
        until: int | None = None,
    ) -> list[dict[str, Any]]:
        """Return a bounded, filterable audit page; callers enforce owner authorization."""
        if not isinstance(limit, int) or isinstance(limit, bool):
            limit = 50
        if not isinstance(offset, int) or isinstance(offset, bool):
            offset = 0
        limit = max(1, min(101, limit))
        offset = max(0, min(1_000_000, offset))
        filters: list[str] = []
        values: list[Any] = []
        if action:
            filters.append("action=?")
            values.append(action[:64])
        if actor_user_id:
            filters.append("actor_user_id=?")
            values.append(actor_user_id[:128])
        if target_user_id:
            filters.append("target_user_id=?")
            values.append(target_user_id[:128])
        if since is not None:
            filters.append("created_at>=?")
            values.append(max(0, since))
        if until is not None:
            filters.append("created_at<=?")
            values.append(max(0, until))
        where = " WHERE " + " AND ".join(filters) if filters else ""
        values.extend((limit, offset))
        with self._connect() as db:
            rows = db.execute(
                """SELECT event_id,actor_user_id,action,target_user_id,details_json,created_at
                   FROM account_audit_events""" + where +
                " ORDER BY event_id DESC LIMIT ? OFFSET ?",
                values,
            ).fetchall()
        return [{
            "eventId": row["event_id"],
            "actorUserId": row["actor_user_id"],
            "action": row["action"],
            "targetUserId": row["target_user_id"],
            "details": json.loads(row["details_json"]),
            "createdAt": row["created_at"],
        } for row in rows]
