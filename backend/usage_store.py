"""Atomic monthly usage reservations for account-scoped AI jobs."""
from __future__ import annotations

import math
import os
import sqlite3
import time
from pathlib import Path
from typing import Any


class UsageLimitError(ValueError):
    def __init__(self, limit: int, period: str):
        super().__init__("Monthly AI usage limit reached.")
        self.limit = limit
        self.period = period


class UsageStore:
    """SQLite-backed monthly AI request counter safe under concurrent requests."""

    def __init__(self, database: str | Path):
        self.database = Path(database)
        self.database.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with sqlite3.connect(self.database, timeout=10) as db:
            db.execute("PRAGMA busy_timeout = 10000")
            db.execute(
                """CREATE TABLE IF NOT EXISTS ai_usage_reservations (
                    user_id TEXT NOT NULL,
                    period TEXT NOT NULL,
                    job_id TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    PRIMARY KEY(user_id, period, job_id)
                )"""
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS ai_usage_period_idx "
                "ON ai_usage_reservations(user_id, period)"
            )
        try:
            os.chmod(self.database, 0o600)
        except OSError:
            pass

    @staticmethod
    def _validated_timestamp(now: int | float | None = None) -> float:
        """Validate a UTC timestamp before calendar conversion or persistence."""
        timestamp = time.time() if now is None else now
        if (
            isinstance(timestamp, bool)
            or not isinstance(timestamp, (int, float))
            or not math.isfinite(timestamp)
        ):
            raise ValueError("Invalid usage timestamp.")
        try:
            time.gmtime(timestamp)
        except (OverflowError, OSError, ValueError) as exc:
            raise ValueError("Invalid usage timestamp.") from exc
        return float(timestamp)

    @classmethod
    def _period(cls, now: int | float | None = None) -> str:
        timestamp = cls._validated_timestamp(now)
        return time.strftime("%Y-%m", time.gmtime(timestamp))

    def release(
        self, user_id: str, job_id: str, period: str
    ) -> bool:
        """Release a reservation when a job could not be accepted by the job store."""
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise ValueError("Invalid account identifier.")
        if not isinstance(job_id, str) or not job_id or len(job_id) > 64:
            raise ValueError("Invalid job identifier.")
        if not isinstance(period, str) or len(period) != 7 or period[4] != "-":
            raise ValueError("Invalid usage period.")
        try:
            parsed_period = time.strptime(period, "%Y-%m")
        except ValueError as exc:
            raise ValueError("Invalid usage period.") from exc
        if time.strftime("%Y-%m", parsed_period) != period:
            raise ValueError("Invalid usage period.")
        db = sqlite3.connect(self.database, timeout=10)
        try:
            db.execute("PRAGMA busy_timeout = 10000")
            db.execute("BEGIN IMMEDIATE")
            cursor = db.execute(
                """DELETE FROM ai_usage_reservations
                   WHERE user_id=? AND period=? AND job_id=?""",
                (user_id, period, job_id),
            )
            db.commit()
            return cursor.rowcount > 0
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def has_reservation(self, user_id: str, job_id: str, limit: int) -> bool:
        """Check that a job has a reservation and its original period is within quota."""
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise ValueError("Invalid account identifier.")
        if not isinstance(job_id, str) or not job_id or len(job_id) > 64:
            raise ValueError("Invalid job identifier.")
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 100000:
            raise ValueError("Invalid monthly usage limit.")
        with sqlite3.connect(self.database, timeout=10) as db:
            db.execute("PRAGMA busy_timeout = 10000")
            row = db.execute(
                """SELECT period FROM ai_usage_reservations
                   WHERE user_id=? AND job_id=? ORDER BY created_at DESC LIMIT 1""",
                (user_id, job_id),
            ).fetchone()
            if row is None:
                return False
            count = db.execute(
                """SELECT COUNT(*) FROM ai_usage_reservations
                   WHERE user_id=? AND period=?""",
                (user_id, row[0]),
            ).fetchone()[0]
            return count <= limit

    def reserve(
        self, user_id: str, job_id: str, limit: int, now: int | float | None = None
    ) -> dict[str, Any]:
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise ValueError("Invalid account identifier.")
        if not isinstance(job_id, str) or not job_id or len(job_id) > 64:
            raise ValueError("Invalid job identifier.")
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 100000:
            raise ValueError("Invalid monthly usage limit.")
        timestamp_value = self._validated_timestamp(now)
        period = time.strftime("%Y-%m", time.gmtime(timestamp_value))
        timestamp = int(timestamp_value)
        db = sqlite3.connect(self.database, timeout=10)
        try:
            db.execute("PRAGMA busy_timeout = 10000")
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute(
                """SELECT 1 FROM ai_usage_reservations
                   WHERE user_id=? AND period=? AND job_id=?""",
                (user_id, period, job_id),
            ).fetchone()
            count = db.execute(
                """SELECT COUNT(*) FROM ai_usage_reservations
                   WHERE user_id=? AND period=?""",
                (user_id, period),
            ).fetchone()[0]
            if existing is None:
                if count >= limit:
                    raise UsageLimitError(limit, period)
                db.execute(
                    """INSERT INTO ai_usage_reservations(user_id,period,job_id,created_at)
                       VALUES(?,?,?,?)""",
                    (user_id, period, job_id, timestamp),
                )
                count += 1
            db.commit()
            try:
                os.chmod(self.database, 0o600)
            except OSError:
                pass
            return {
                "period": period,
                "used": count,
                "limit": limit,
                "remaining": max(0, limit - count),
            }
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()


    def summary(self, user_id: str, limit: int, now: int | float | None = None) -> dict[str, Any]:
        """Return the authenticated account's monthly reservation count and quota."""
        if not isinstance(user_id, str) or not user_id or len(user_id) > 128:
            raise ValueError("Invalid account identifier.")
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 100000:
            raise ValueError("Invalid monthly usage limit.")
        period = self._period(now)
        with sqlite3.connect(self.database, timeout=10) as db:
            db.execute("PRAGMA busy_timeout = 10000")
            used = db.execute(
                "SELECT COUNT(*) FROM ai_usage_reservations WHERE user_id=? AND period=?",
                (user_id, period),
            ).fetchone()[0]
        return {
            "period": period,
            "used": used,
            "limit": limit,
            "remaining": max(0, limit - used),
            "exhausted": used >= limit,
        }
