"""Premium entitlement and family-seat ledger foundation.

No payment provider is integrated here. Grants change application entitlement
only; they do not waive infrastructure, storage, or AI-provider costs.
"""
from __future__ import annotations

import sqlite3
import time
import uuid
from pathlib import Path


class EntitlementError(ValueError):
    pass


class EntitlementStore:
    def __init__(self, database: str | Path):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS premium_grants (
                grant_id TEXT PRIMARY KEY, user_id TEXT NOT NULL,
                plan TEXT NOT NULL CHECK(plan IN ('premium','family')),
                starts_at INTEGER NOT NULL, expires_at INTEGER,
                revoked_at INTEGER, actor_user_id TEXT NOT NULL,
                reason TEXT NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS premium_user_idx ON premium_grants(user_id, starts_at, expires_at)")
            db.execute("""CREATE TABLE IF NOT EXISTS family_members (
                family_id TEXT NOT NULL, user_id TEXT NOT NULL,
                added_at INTEGER NOT NULL, removed_at INTEGER,
                PRIMARY KEY(family_id,user_id)
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS family_member_idx ON family_members(user_id, removed_at)")
            db.execute("""CREATE TABLE IF NOT EXISTS family_groups (
                family_id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL UNIQUE,
                seat_limit INTEGER NOT NULL CHECK(seat_limit BETWEEN 2 AND 10),
                created_at INTEGER NOT NULL
            )""")

    def _connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    def grant(
        self, actor_role: str, actor_user_id: str, user_id: str, plan: str,
        expires_at: int | None = None, reason: str = "owner complimentary grant",
    ) -> str:
        if actor_role != "owner":
            raise EntitlementError("Operazione riservata al proprietario.")
        if plan not in {"premium", "family"} or not user_id or len(user_id) > 128:
            raise EntitlementError("Piano o account non valido.")
        now = int(time.time())
        if expires_at is not None and (not isinstance(expires_at, int) or expires_at <= now):
            raise EntitlementError("La scadenza deve essere futura.")
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 240:
            raise EntitlementError("Motivazione non valida.")
        grant_id = uuid.uuid4().hex
        with self._connect() as db:
            db.execute(
                """INSERT INTO premium_grants
                   (grant_id,user_id,plan,starts_at,expires_at,actor_user_id,reason)
                   VALUES(?,?,?,?,?,?,?)""",
                (grant_id, user_id, plan, now, expires_at, actor_user_id, reason.strip()),
            )
        return grant_id

    def revoke(self, actor_role: str, grant_id: str) -> bool:
        if actor_role != "owner":
            raise EntitlementError("Operazione riservata al proprietario.")
        with self._connect() as db:
            result = db.execute(
                "UPDATE premium_grants SET revoked_at=? WHERE grant_id=? AND revoked_at IS NULL",
                (int(time.time()), grant_id),
            )
            return result.rowcount == 1

    def create_family(self, owner_user_id: str, family_id: str | None = None, seat_limit: int = 5) -> str:
        family_id = family_id or uuid.uuid4().hex
        if not family_id or len(family_id) > 64 or not isinstance(seat_limit, int) or not 2 <= seat_limit <= 10:
            raise EntitlementError("Identificativo famiglia o limite posti non valido.")
        with self._connect() as db:
            db.execute(
                "INSERT INTO family_groups(family_id,owner_user_id,seat_limit,created_at) VALUES(?,?,?,?)",
                (family_id, owner_user_id, seat_limit, int(time.time())),
            )
            db.execute(
                "INSERT INTO family_members(family_id,user_id,added_at) VALUES(?,?,?)",
                (family_id, owner_user_id, int(time.time())),
            )
        return family_id

    def add_family_member(
        self, family_id: str, actor_user_id: str, user_id: str
    ) -> None:
        if not user_id or len(user_id) > 128:
            raise EntitlementError("Account non valido.")
        now = int(time.time())
        with self._connect() as db:
            owner = db.execute(
                "SELECT seat_limit FROM family_groups WHERE family_id=? AND owner_user_id=?",
                (family_id, actor_user_id),
            ).fetchone()
            if owner is None:
                raise EntitlementError("Solo il titolare della famiglia può invitare membri.")
            count = db.execute(
                "SELECT COUNT(*) AS n FROM family_members WHERE family_id=? AND removed_at IS NULL",
                (family_id,),
            ).fetchone()["n"]
            if count >= owner["seat_limit"]:
                raise EntitlementError("Numero massimo di posti famiglia raggiunto.")
            try:
                db.execute(
                    "INSERT INTO family_members(family_id,user_id,added_at) VALUES(?,?,?)",
                    (family_id, user_id, now),
                )
            except sqlite3.IntegrityError as exc:
                raise EntitlementError("Account già presente nella famiglia.") from exc

    def remove_family_member(self, family_id: str, actor_user_id: str, user_id: str) -> bool:
        """Remove a family seat; only the immutable family owner may do so."""
        if not user_id or len(user_id) > 128:
            raise EntitlementError("Account non valido.")
        with self._connect() as db:
            owner = db.execute(
                "SELECT 1 FROM family_groups WHERE family_id=? AND owner_user_id=?",
                (family_id, actor_user_id),
            ).fetchone()
            if owner is None:
                raise EntitlementError("Solo il titolare della famiglia può rimuovere membri.")
            if user_id == actor_user_id:
                raise EntitlementError("Il titolare non può rimuovere sé stesso.")
            result = db.execute(
                """UPDATE family_members SET removed_at=?
                   WHERE family_id=? AND user_id=? AND removed_at IS NULL""",
                (int(time.time()), family_id, user_id),
            )
            return result.rowcount == 1

    def list_grants(self, actor_role: str, user_id: str, limit: int = 50) -> list[dict]:
        """Return grant metadata without secrets; owner-only."""
        if actor_role != "owner":
            raise EntitlementError("Operazione riservata al proprietario.")
        if not isinstance(limit, int) or isinstance(limit, bool):
            limit = 50
        limit = max(1, min(100, limit))
        with self._connect() as db:
            rows = db.execute(
                """SELECT grant_id,user_id,plan,starts_at,expires_at,revoked_at,
                          actor_user_id,reason
                   FROM premium_grants WHERE user_id=?
                   ORDER BY starts_at DESC,grant_id LIMIT ?""",
                (user_id, limit),
            ).fetchall()
        return [dict(row) for row in rows]

    def entitlement_details(self, user_id: str, now: int | None = None) -> dict:
        """Return the active grant metadata for the signed-in account."""
        current = int(time.time()) if now is None else now
        with self._connect() as db:
            own = db.execute(
                """SELECT plan,expires_at FROM premium_grants
                   WHERE user_id=? AND revoked_at IS NULL
                   AND starts_at<=? AND (expires_at IS NULL OR expires_at>?)
                   ORDER BY starts_at DESC,grant_id LIMIT 1""",
                (user_id, current, current),
            ).fetchone()
            if own is not None:
                return {
                    "tier": "premium",
                    "isPremium": True,
                    "plan": own["plan"],
                    "validUntil": own["expires_at"],
                    "source": "promotion",
                }
            family = db.execute(
                """SELECT pg.expires_at FROM family_members fm
                   JOIN family_groups fg ON fg.family_id=fm.family_id
                   JOIN premium_grants pg ON pg.user_id=fg.owner_user_id
                   WHERE fm.user_id=? AND fm.removed_at IS NULL
                   AND pg.plan='family' AND pg.revoked_at IS NULL
                   AND pg.starts_at<=? AND (pg.expires_at IS NULL OR pg.expires_at>?)
                   ORDER BY pg.starts_at DESC,pg.grant_id LIMIT 1""",
                (user_id, current, current),
            ).fetchone()
        if family is not None:
            return {
                "tier": "premium",
                "isPremium": True,
                "plan": "family",
                "validUntil": family["expires_at"],
                "source": "promotion",
            }
        return {
            "tier": "free",
            "isPremium": False,
            "plan": None,
            "validUntil": None,
            "source": None,
        }

    def has_premium(self, user_id: str, now: int | None = None) -> bool:
        current = int(time.time()) if now is None else now
        with self._connect() as db:
            own = db.execute(
                """SELECT 1 FROM premium_grants WHERE user_id=? AND revoked_at IS NULL
                   AND starts_at<=? AND (expires_at IS NULL OR expires_at>?) LIMIT 1""",
                (user_id, current, current),
            ).fetchone()
            if own:
                return True
            family = db.execute(
                """SELECT 1 FROM family_members fm
                   JOIN family_groups fg ON fg.family_id=fm.family_id
                   JOIN premium_grants pg ON pg.user_id=fg.owner_user_id
                   WHERE fm.user_id=? AND fm.removed_at IS NULL
                   AND pg.plan='family' AND pg.revoked_at IS NULL
                   AND pg.starts_at<=? AND (pg.expires_at IS NULL OR pg.expires_at>?)
                   LIMIT 1""",
                (user_id, current, current),
            ).fetchone()
            return family is not None
