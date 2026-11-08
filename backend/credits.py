"""Atomic AI credit ledger with idempotent grants, charges and refunds."""
from __future__ import annotations

import sqlite3
import time
import uuid
from pathlib import Path


class CreditError(ValueError):
    pass


class CreditStore:
    def __init__(self, database: str | Path):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS ai_credit_balances (
                user_id TEXT PRIMARY KEY,
                balance INTEGER NOT NULL DEFAULT 0 CHECK(balance >= 0),
                updated_at INTEGER NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS ai_credit_transactions (
                transaction_id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                kind TEXT NOT NULL CHECK(kind IN ('grant','consume','refund')),
                amount INTEGER NOT NULL CHECK(amount > 0),
                reference_id TEXT NOT NULL,
                actor_user_id TEXT NOT NULL,
                reason TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                UNIQUE(user_id,kind,reference_id)
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS ai_credit_user_idx ON ai_credit_transactions(user_id,created_at DESC)")

    def _connect(self):
        db = sqlite3.connect(self.database, timeout=15)
        db.row_factory = sqlite3.Row
        return db

    @staticmethod
    def _validate(user_id: str, amount: int, reference_id: str):
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise CreditError("Account non valido.")
        if not isinstance(amount, int) or isinstance(amount, bool) or not 1 <= amount <= 1_000_000:
            raise CreditError("Quantità crediti non valida.")
        if not isinstance(reference_id, str) or not reference_id or len(reference_id) > 128:
            raise CreditError("Riferimento operazione non valido.")

    def balance(self, user_id: str) -> dict:
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise CreditError("Account non valido.")
        with self._connect() as db:
            row = db.execute(
                "SELECT balance,updated_at FROM ai_credit_balances WHERE user_id=?",
                (user_id,),
            ).fetchone()
        return {"userId": user_id, "balance": row["balance"] if row else 0,
                "updatedAt": row["updated_at"] if row else None}

    def grant(self, actor_role: str, actor_user_id: str, user_id: str,
              amount: int, reference_id: str, reason: str) -> dict:
        if actor_role != "owner":
            raise CreditError("Solo il proprietario può assegnare crediti.")
        self._validate(user_id, amount, reference_id)
        if not actor_user_id or len(actor_user_id) > 128:
            raise CreditError("Operatore non valido.")
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 240:
            raise CreditError("Motivazione non valida.")
        return self._apply(user_id, "grant", amount, reference_id, actor_user_id, reason.strip())

    def consume(self, user_id: str, amount: int, reference_id: str,
                reason: str = "AI processing") -> dict:
        self._validate(user_id, amount, reference_id)
        return self._apply(user_id, "consume", amount, reference_id, user_id, reason)

    def refund(self, user_id: str, amount: int, reference_id: str,
               actor_user_id: str = "system", reason: str = "AI job refund") -> dict:
        self._validate(user_id, amount, reference_id)
        return self._apply(user_id, "refund", amount, reference_id, actor_user_id, reason)

    def _apply(self, user_id: str, kind: str, amount: int, reference_id: str,
               actor_user_id: str, reason: str) -> dict:
        now = int(time.time())
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute(
                """SELECT transaction_id,amount FROM ai_credit_transactions
                   WHERE user_id=? AND kind=? AND reference_id=?""",
                (user_id, kind, reference_id),
            ).fetchone()
            if existing:
                if existing["amount"] != amount:
                    raise CreditError("Riferimento già utilizzato con una quantità diversa.")
                row = db.execute(
                    "SELECT balance FROM ai_credit_balances WHERE user_id=?",
                    (user_id,),
                ).fetchone()
                return {"transactionId": existing["transaction_id"],
                        "balance": row["balance"] if row else 0,
                        "applied": False, "kind": kind}
            row = db.execute(
                "SELECT balance FROM ai_credit_balances WHERE user_id=?",
                (user_id,),
            ).fetchone()
            balance = row["balance"] if row else 0
            if kind == "consume" and balance < amount:
                raise CreditError("Crediti insufficienti.")
            if kind == "refund":
                original = db.execute(
                    """SELECT COALESCE(SUM(amount),0) AS n FROM ai_credit_transactions
                       WHERE user_id=? AND kind='consume' AND reference_id=?""",
                    (user_id, reference_id),
                ).fetchone()["n"]
                refunded = db.execute(
                    """SELECT COALESCE(SUM(amount),0) AS n FROM ai_credit_transactions
                       WHERE user_id=? AND kind='refund' AND reference_id=?""",
                    (user_id, reference_id),
                ).fetchone()["n"]
                if original <= 0 or refunded + amount > original:
                    raise CreditError("Rimborso superiore al consumo originale.")
            next_balance = balance + amount if kind in {"grant", "refund"} else balance - amount
            transaction_id = uuid.uuid4().hex
            db.execute(
                """INSERT INTO ai_credit_transactions
                   (transaction_id,user_id,kind,amount,reference_id,actor_user_id,reason,created_at)
                   VALUES(?,?,?,?,?,?,?,?)""",
                (transaction_id, user_id, kind, amount, reference_id, actor_user_id, reason, now),
            )
            db.execute(
                """INSERT INTO ai_credit_balances(user_id,balance,updated_at)
                   VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET
                   balance=excluded.balance,updated_at=excluded.updated_at""",
                (user_id, next_balance, now),
            )
        return {"transactionId": transaction_id, "balance": next_balance,
                "applied": True, "kind": kind}

    def history(self, user_id: str, limit: int = 50) -> list[dict]:
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise CreditError("Account non valido.")
        limit = max(1, min(100, limit if isinstance(limit, int) and not isinstance(limit, bool) else 50))
        with self._connect() as db:
            rows = db.execute(
                """SELECT transaction_id,kind,amount,reference_id,reason,created_at
                   FROM ai_credit_transactions WHERE user_id=?
                   ORDER BY created_at DESC,transaction_id LIMIT ?""",
                (user_id, limit),
            ).fetchall()
        return [dict(row) for row in rows]
