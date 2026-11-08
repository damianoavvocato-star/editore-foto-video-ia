"""Deny-by-default role and per-account permission policy.

This module is a policy foundation. HTTP routes must pass the role resolved from
the authenticated session; never accept actor_role from request JSON.
"""
from __future__ import annotations

import sqlite3
import time
from pathlib import Path

PERMISSIONS = frozenset({
    "accounts.read", "accounts.create", "accounts.update", "accounts.disable",
    "accounts.password_reset", "audit.read", "media.support_read",
    "billing.read", "billing.grant", "family.manage", "settings.manage",
})

ROLE_DEFAULTS = {
    "owner": PERMISSIONS,
    "admin": frozenset({"accounts.read", "accounts.create", "accounts.update",
                        "accounts.disable", "accounts.password_reset",
                        "media.support_read", "billing.read", "family.manage"}),
    "support": frozenset({"accounts.read", "accounts.password_reset",
                          "media.support_read", "billing.read"}),
    "collaborator": frozenset({"billing.read"}),
    "user": frozenset(),
}


class PermissionError(ValueError):
    pass


class PermissionPolicy:
    """Persistent explicit allow/deny overrides, with owner-only administration."""

    def __init__(self, database: str | Path):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS permission_overrides (
                user_id TEXT NOT NULL,
                permission TEXT NOT NULL,
                effect TEXT NOT NULL CHECK(effect IN ('allow','deny')),
                updated_at INTEGER NOT NULL,
                PRIMARY KEY(user_id, permission)
            )""")

    def _connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    def has_permission(self, user_id: str, role: str, permission: str) -> bool:
        if role not in ROLE_DEFAULTS or permission not in PERMISSIONS:
            return False
        if role == "owner":
            return True
        with self._connect() as db:
            row = db.execute(
                "SELECT effect FROM permission_overrides WHERE user_id=? AND permission=?",
                (user_id, permission),
            ).fetchone()
        if row is not None:
            return row["effect"] == "allow"
        return permission in ROLE_DEFAULTS[role]

    def set_override(
        self, actor_role: str, user_id: str, permission: str, effect: str
    ) -> None:
        if actor_role != "owner":
            raise PermissionError("Operazione riservata al proprietario.")
        if not user_id or len(user_id) > 128:
            raise PermissionError("Account destinatario non valido.")
        if permission not in PERMISSIONS or effect not in {"allow", "deny"}:
            raise PermissionError("Permesso o effetto non valido.")
        with self._connect() as db:
            db.execute(
                """INSERT INTO permission_overrides(user_id,permission,effect,updated_at)
                   VALUES(?,?,?,?) ON CONFLICT(user_id,permission) DO UPDATE SET
                   effect=excluded.effect,updated_at=excluded.updated_at""",
                (user_id, permission, effect, int(time.time())),
            )

    def list_overrides(self, actor_role: str, user_id: str) -> list[dict]:
        if actor_role != "owner":
            raise PermissionError("Operazione riservata al proprietario.")
        with self._connect() as db:
            rows = db.execute(
                """SELECT permission,effect,updated_at FROM permission_overrides
                   WHERE user_id=? ORDER BY permission""",
                (user_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def effective_permissions(self, user_id: str, role: str) -> list[str]:
        if role not in ROLE_DEFAULTS:
            return []
        return sorted(permission for permission in PERMISSIONS
                      if self.has_permission(user_id, role, permission))

    def remove_override(
        self, actor_role: str, user_id: str, permission: str
    ) -> bool:
        if actor_role != "owner":
            raise PermissionError("Operazione riservata al proprietario.")
        if permission not in PERMISSIONS:
            raise PermissionError("Permesso non valido.")
        with self._connect() as db:
            result = db.execute(
                "DELETE FROM permission_overrides WHERE user_id=? AND permission=?",
                (user_id, permission),
            )
            return result.rowcount == 1
