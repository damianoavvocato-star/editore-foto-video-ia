"""Durable, provider-neutral queue for reviewed Studio generation jobs.

This queue does not call external providers. Workers must persist a submission
before making any billable request and reconcile ambiguous submissions rather
than blindly retrying them.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from backend.studio import StudioJobRequest, StudioRequestError


PROVIDER_STATES = {"in_progress", "complete", "error", "rejected"}
ERROR_CODE_PATTERN = re.compile(r"^[a-z0-9_.-]{1,64}$")


class StudioQueueError(ValueError):
    """A queue operation is invalid or violates the job state machine."""


class StudioJobQueue:
    """SQLite queue with account isolation, idempotency and worker leases."""

    def __init__(self, database: str | Path, lease_seconds: int = 120):
        self.database = Path(database)
        self.database.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lease_seconds = max(15, min(int(lease_seconds), 900))
        with self._connection() as connection:
            connection.execute(
                """CREATE TABLE IF NOT EXISTS studio_queue_jobs (
                    job_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    request_hash TEXT NOT NULL,
                    idempotency_key TEXT,
                    state TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    max_attempts INTEGER NOT NULL DEFAULT 3,
                    next_retry_at REAL NOT NULL DEFAULT 0,
                    provider_video_id TEXT,
                    provider_status TEXT,
                    last_error_code TEXT,
                    lease_owner TEXT,
                    lease_expires_at REAL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )"""
            )
            connection.execute(
                """CREATE UNIQUE INDEX IF NOT EXISTS studio_queue_user_idempotency
                   ON studio_queue_jobs(user_id, idempotency_key)
                   WHERE idempotency_key IS NOT NULL"""
            )
            connection.execute(
                """CREATE INDEX IF NOT EXISTS studio_queue_ready
                   ON studio_queue_jobs(state, next_retry_at, created_at)"""
            )
        self._restrict_permissions()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 10000")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _restrict_permissions(self) -> None:
        try:
            os.chmod(self.database, 0o600)
            os.chmod(self.database.parent, 0o700)
        except OSError:
            pass

    @staticmethod
    def _serialize(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "jobId": row["job_id"],
            "state": row["state"],
            "request": json.loads(row["payload"]),
            "attempts": row["attempts"],
            "maxAttempts": row["max_attempts"],
            "providerVideoId": row["provider_video_id"],
            "providerStatus": row["provider_status"],
            "lastErrorCode": row["last_error_code"],
            "leaseOwner": row["lease_owner"],
            "leaseExpiresAt": row["lease_expires_at"],
            "nextRetryAt": row["next_retry_at"],
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }

    def enqueue(
        self,
        user_id: str,
        request: StudioJobRequest,
        idempotency_key: str | None = None,
        max_attempts: int = 3,
        now: float | None = None,
    ) -> tuple[dict[str, Any], bool]:
        if not user_id:
            raise StudioQueueError("Account obbligatorio.")
        if idempotency_key is not None and (
            not idempotency_key or len(idempotency_key) > 128
            or any(ord(char) < 33 for char in idempotency_key)
        ):
            raise StudioQueueError("Chiave idempotenza non valida.")
        if not 1 <= max_attempts <= 5:
            raise StudioQueueError("Numero massimo di tentativi non valido.")
        try:
            request.validate_policy()
        except StudioRequestError:
            raise
        payload = request.model_dump()
        canonical = json.dumps(
            payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")
        )
        fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        timestamp = time.time() if now is None else float(now)
        job_id = uuid.uuid4().hex
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            if idempotency_key is not None:
                existing = connection.execute(
                    "SELECT * FROM studio_queue_jobs WHERE user_id=? AND idempotency_key=?",
                    (user_id, idempotency_key),
                ).fetchone()
                if existing:
                    if existing["request_hash"] != fingerprint:
                        raise StudioQueueError(
                            "Chiave idempotenza già usata per una richiesta differente."
                        )
                    connection.rollback()
                    return self._serialize(existing), False
            connection.execute(
                """INSERT INTO studio_queue_jobs(
                    job_id, user_id, payload, request_hash, idempotency_key,
                    state, attempts, max_attempts, next_retry_at, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 'queued', 0, ?, ?, ?, ?)""",
                (
                    job_id, user_id, canonical, fingerprint, idempotency_key,
                    max_attempts, timestamp, timestamp, timestamp,
                ),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
        self._restrict_permissions()
        return {
            "jobId": job_id, "state": "queued", "request": payload,
            "attempts": 0, "maxAttempts": max_attempts,
            "providerVideoId": None, "providerStatus": None,
            "lastErrorCode": None, "leaseOwner": None,
            "leaseExpiresAt": None, "nextRetryAt": timestamp,
            "createdAt": timestamp, "updatedAt": timestamp,
        }, True

    def claim_next(
        self, worker_id: str, now: float | None = None
    ) -> dict[str, Any] | None:
        if not worker_id or len(worker_id) > 128:
            raise StudioQueueError("Identificativo worker non valido.")
        timestamp = time.time() if now is None else float(now)
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            # A lost response after provider acceptance is ambiguous. Do not
            # resubmit it automatically: it could create a duplicate paid video.
            connection.execute(
                """UPDATE studio_queue_jobs
                   SET state='failed', last_error_code='submission_outcome_unknown',
                       lease_owner=NULL, lease_expires_at=NULL, updated_at=?
                   WHERE state='submitting' AND lease_expires_at <= ?""",
                (timestamp, timestamp),
            )
            row = connection.execute(
                """SELECT * FROM studio_queue_jobs
                   WHERE state='queued' AND next_retry_at <= ?
                   ORDER BY created_at ASC LIMIT 1""",
                (timestamp,),
            ).fetchone()
            if row is None:
                connection.commit()
                return None
            expires = timestamp + self.lease_seconds
            connection.execute(
                """UPDATE studio_queue_jobs
                   SET state='submitting', attempts=attempts+1,
                       lease_owner=?, lease_expires_at=?, updated_at=?
                   WHERE job_id=? AND state='queued'""",
                (worker_id, expires, timestamp, row["job_id"]),
            )
            claimed = connection.execute(
                "SELECT * FROM studio_queue_jobs WHERE job_id=?",
                (row["job_id"],),
            ).fetchone()
            connection.commit()
            return self._serialize(claimed)
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def mark_submitted(
        self,
        worker_id: str,
        job_id: str,
        provider_video_id: str,
        provider_status: str = "in_progress",
        now: float | None = None,
    ) -> dict[str, Any]:
        if not provider_video_id or len(provider_video_id) > 128:
            raise StudioQueueError("Identificativo video provider non valido.")
        if provider_status not in PROVIDER_STATES:
            raise StudioQueueError("Stato provider non valido.")
        timestamp = time.time() if now is None else float(now)
        with self._connection() as connection:
            cursor = connection.execute(
                """UPDATE studio_queue_jobs
                   SET state=?, provider_video_id=?, provider_status=?,
                       lease_owner=NULL, lease_expires_at=NULL,
                       last_error_code=NULL, updated_at=?
                   WHERE job_id=? AND state='submitting' AND lease_owner=?
                     AND lease_expires_at > ?""",
                (
                    "completed" if provider_status == "complete" else
                    "failed" if provider_status in {"error", "rejected"} else "processing",
                    provider_video_id, provider_status, timestamp,
                    job_id, worker_id, timestamp,
                ),
            )
            if cursor.rowcount != 1:
                raise StudioQueueError("Lease scaduta o job non assegnato a questo worker.")
            row = connection.execute(
                "SELECT * FROM studio_queue_jobs WHERE job_id=?", (job_id,)
            ).fetchone()
        return self._serialize(row)

    def record_provider_status(
        self,
        user_id: str,
        job_id: str,
        provider_status: str,
        now: float | None = None,
    ) -> dict[str, Any]:
        if provider_status not in PROVIDER_STATES:
            raise StudioQueueError("Stato provider non valido.")
        timestamp = time.time() if now is None else float(now)
        state = (
            "completed" if provider_status == "complete" else
            "failed" if provider_status in {"error", "rejected"} else "processing"
        )
        with self._connection() as connection:
            cursor = connection.execute(
                """UPDATE studio_queue_jobs SET state=?, provider_status=?, updated_at=?
                   WHERE job_id=? AND user_id=? AND state='processing'""",
                (state, provider_status, timestamp, job_id, user_id),
            )
            if cursor.rowcount != 1:
                raise StudioQueueError("Job non trovato o non aggiornabile.")
            row = connection.execute(
                "SELECT * FROM studio_queue_jobs WHERE job_id=?", (job_id,)
            ).fetchone()
        return self._serialize(row)

    def schedule_retry(
        self,
        worker_id: str,
        job_id: str,
        error_code: str,
        retry_delay_seconds: int = 30,
        now: float | None = None,
    ) -> dict[str, Any]:
        if not ERROR_CODE_PATTERN.fullmatch(error_code or ""):
            raise StudioQueueError("Codice errore non valido.")
        delay = max(1, min(int(retry_delay_seconds), 3600))
        timestamp = time.time() if now is None else float(now)
        with self._connection() as connection:
            row = connection.execute(
                """SELECT * FROM studio_queue_jobs
                   WHERE job_id=? AND state='submitting' AND lease_owner=?""",
                (job_id, worker_id),
            ).fetchone()
            if row is None or row["lease_expires_at"] is None or row["lease_expires_at"] <= timestamp:
                raise StudioQueueError("Lease scaduta o job non assegnato a questo worker.")
            retry = row["attempts"] < row["max_attempts"]
            connection.execute(
                """UPDATE studio_queue_jobs
                   SET state=?, next_retry_at=?, last_error_code=?,
                       lease_owner=NULL, lease_expires_at=NULL, updated_at=?
                   WHERE job_id=?""",
                (
                    "queued" if retry else "failed",
                    timestamp + delay if retry else timestamp,
                    error_code, timestamp, job_id,
                ),
            )
            updated = connection.execute(
                "SELECT * FROM studio_queue_jobs WHERE job_id=?", (job_id,)
            ).fetchone()
        return self._serialize(updated)

    def get(self, user_id: str, job_id: str) -> dict[str, Any] | None:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT * FROM studio_queue_jobs WHERE user_id=? AND job_id=?",
                (user_id, job_id),
            ).fetchone()
        return self._serialize(row) if row else None

    def list_for_user(self, user_id: str, limit: int = 50) -> list[dict[str, Any]]:
        bounded = max(1, min(100, int(limit)))
        with self._connection() as connection:
            rows = connection.execute(
                """SELECT * FROM studio_queue_jobs WHERE user_id=?
                   ORDER BY created_at DESC LIMIT ?""",
                (user_id, bounded),
            ).fetchall()
        return [self._serialize(row) for row in rows]
