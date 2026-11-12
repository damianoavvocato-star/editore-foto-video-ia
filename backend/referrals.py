"""Abuse-resistant, one-claim-per-invitee Premium referral ledger.

Rewards mature after seven days. Both rewards are inserted atomically into the
existing premium_grants ledger and start at maturation, not at claim time.
"""
from __future__ import annotations

import re
import secrets
import sqlite3
import time
from pathlib import Path

from backend.accounts import _append_audit_event
from backend.entitlements import EntitlementStore


class ReferralError(ValueError):
    pass


class ReferralStore:
    MATURATION_SECONDS = 7 * 24 * 60 * 60
    REWARD_SECONDS = 30 * 24 * 60 * 60

    def __init__(self, database: str | Path):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        # Referral rewards are Premium grants; ensure their ledger schema exists.
        EntitlementStore(self.database)
        with self._connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS referral_codes (
                user_id TEXT PRIMARY KEY,
                code TEXT NOT NULL UNIQUE,
                created_at INTEGER NOT NULL,
                revoked_at INTEGER
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS referral_claims (
                claim_id TEXT PRIMARY KEY,
                code TEXT NOT NULL,
                inviter_user_id TEXT NOT NULL,
                invitee_user_id TEXT NOT NULL UNIQUE,
                claimed_at INTEGER NOT NULL,
                eligible_at INTEGER NOT NULL,
                matured_at INTEGER,
                status TEXT NOT NULL CHECK(status IN ('pending','rewarded','rejected'))
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS referral_maturity_idx ON referral_claims(status,eligible_at)")
            db.execute("CREATE INDEX IF NOT EXISTS referral_inviter_idx ON referral_claims(inviter_user_id,claimed_at DESC)")

    def _connect(self):
        db = sqlite3.connect(self.database, timeout=15)
        db.row_factory = sqlite3.Row
        return db

    @staticmethod
    def _active_account(db, user_id: str) -> bool:
        row = db.execute(
            "SELECT 1 FROM accounts WHERE user_id=? AND disabled_at IS NULL",
            (user_id,),
        ).fetchone()
        return row is not None

    def create_or_get_code(self, user_id: str) -> str:
        if not isinstance(user_id, str):
            raise ReferralError("Account non valido.")
        user_id = user_id.strip()
        if not user_id or len(user_id) > 128:
            raise ReferralError("Account non valido.")
        with self._connect() as db:
            # Serialize the read-then-create sequence so concurrent requests
            # for one account return the same code instead of racing on UNIQUE.
            db.execute("BEGIN IMMEDIATE")
            if not self._active_account(db, user_id):
                raise ReferralError("Account non attivo.")
            row = db.execute(
                "SELECT code FROM referral_codes WHERE user_id=? AND revoked_at IS NULL",
                (user_id,),
            ).fetchone()
            if row:
                return row["code"]
            for _ in range(8):
                code = secrets.token_hex(5).upper()
                try:
                    db.execute(
                        "INSERT INTO referral_codes(user_id,code,created_at) VALUES(?,?,?)",
                        (user_id, code, int(time.time())),
                    )
                    return code
                except sqlite3.IntegrityError:
                    continue
        raise ReferralError("Impossibile generare un codice invito. Riprova.")

    def claim(self, invitee_user_id: str, code: str, now: int | None = None) -> dict:
        if not isinstance(code, str):
            raise ReferralError("Codice invito non valido.")
        normalized = code.strip().upper()
        if re.fullmatch(r"[A-Z0-9]{6,12}", normalized, flags=re.ASCII) is None:
            raise ReferralError("Codice invito non valido.")
        if not isinstance(invitee_user_id, str):
            raise ReferralError("Account non valido.")
        invitee_user_id = invitee_user_id.strip()
        if not invitee_user_id or len(invitee_user_id) > 128:
            raise ReferralError("Account non valido.")
        current = int(time.time()) if now is None else int(now)
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            inviter = db.execute(
                """SELECT rc.user_id FROM referral_codes rc
                   WHERE rc.code=? AND rc.revoked_at IS NULL""",
                (normalized,),
            ).fetchone()
            if inviter is None:
                raise ReferralError("Codice invito inesistente o non attivo.")
            inviter_id = inviter["user_id"]
            if inviter_id == invitee_user_id:
                raise ReferralError("Non puoi utilizzare il tuo stesso codice.")
            if not self._active_account(db, inviter_id) or not self._active_account(db, invitee_user_id):
                raise ReferralError("Entrambi gli account devono essere attivi.")
            existing = db.execute(
                "SELECT 1 FROM referral_claims WHERE invitee_user_id=?",
                (invitee_user_id,),
            ).fetchone()
            if existing:
                raise ReferralError("Questo account ha già utilizzato un codice invito.")
            claim_id = secrets.token_hex(16)
            eligible_at = current + self.MATURATION_SECONDS
            db.execute(
                """INSERT INTO referral_claims
                   (claim_id,code,inviter_user_id,invitee_user_id,claimed_at,eligible_at,status)
                   VALUES(?,?,?,?,?,?, 'pending')""",
                (claim_id, normalized, inviter_id, invitee_user_id, current, eligible_at),
            )
            _append_audit_event(
                db, invitee_user_id, "referral.claimed", inviter_id,
                {"status": "pending", "maturationDays": 7}, current,
            )
        return {
            "claimId": claim_id,
            "status": "pending",
            "eligibleAt": eligible_at,
            "rewardDays": 30,
        }

    def mature_due(self, now: int | None = None) -> int:
        current = int(time.time()) if now is None else int(now)
        matured = 0
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            rows = db.execute(
                """SELECT claim_id,inviter_user_id,invitee_user_id
                   FROM referral_claims WHERE status='pending' AND eligible_at<=?
                   ORDER BY eligible_at,claim_id""",
                (current,),
            ).fetchall()
            for row in rows:
                if not self._active_account(db, row["inviter_user_id"]) or not self._active_account(db, row["invitee_user_id"]):
                    db.execute(
                        "UPDATE referral_claims SET status='rejected' WHERE claim_id=? AND status='pending'",
                        (row["claim_id"],),
                    )
                    continue
                expires = current + self.REWARD_SECONDS
                for beneficiary in (row["inviter_user_id"], row["invitee_user_id"]):
                    db.execute(
                        """INSERT INTO premium_grants
                           (grant_id,user_id,plan,starts_at,expires_at,actor_user_id,reason)
                           VALUES(?,?,'premium',?,?,?,'referral reward: 30 days')""",
                        (secrets.token_hex(16), beneficiary, current, expires, "referral-system"),
                    )
                db.execute(
                    """UPDATE referral_claims SET status='rewarded',matured_at=?
                       WHERE claim_id=? AND status='pending'""",
                    (current, row["claim_id"]),
                )
                _append_audit_event(
                    db, row["inviter_user_id"], "referral.rewarded", row["invitee_user_id"],
                    {"rewardDays": 30, "beneficiaries": 2}, current,
                )
                matured += 1
        return matured

    def history(self, user_id: str, now: int | None = None) -> dict:
        self.mature_due(now)
        with self._connect() as db:
            code = db.execute(
                "SELECT code FROM referral_codes WHERE user_id=? AND revoked_at IS NULL",
                (user_id,),
            ).fetchone()
            rows = db.execute(
                """SELECT claim_id,inviter_user_id,invitee_user_id,claimed_at,
                          eligible_at,matured_at,status
                   FROM referral_claims
                   WHERE inviter_user_id=? OR invitee_user_id=?
                   ORDER BY claimed_at DESC LIMIT 100""",
                (user_id, user_id),
            ).fetchall()
        return {
            "code": code["code"] if code else None,
            "claims": [
                {
                    "claimId": row["claim_id"],
                    "role": "inviter" if row["inviter_user_id"] == user_id else "invitee",
                    "status": row["status"],
                    "claimedAt": row["claimed_at"],
                    "eligibleAt": row["eligible_at"],
                    "maturedAt": row["matured_at"],
                    "rewardDays": 30 if row["status"] == "rewarded" else 0,
                }
                for row in rows
            ],
        }
