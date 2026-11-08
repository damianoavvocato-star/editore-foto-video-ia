"""Durable, private storage for asynchronous media job status.

Queued/running jobs are marked failed on process restart because their worker
threads cannot be resumed safely. Completed MagicIAedit proposals and render
metadata remain available across restarts.
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
from contextlib import contextmanager
from typing import Iterator
from pathlib import Path
from typing import Any


class _PersistentJob(dict):
    def __init__(self, job_id: str, values: dict[str, Any], registry: "JobRegistry"):
        super().__init__(values)
        self._job_id = job_id
        self._registry = registry

    def update(self, *args: Any, **kwargs: Any) -> None:
        super().update(*args, **kwargs)
        self._registry._save(self._job_id, self)

    def __setitem__(self, key: str, value: Any) -> None:
        super().__setitem__(key, value)
        self._registry._save(self._job_id, self)

    def __delitem__(self, key: str) -> None:
        super().__delitem__(key)
        self._registry._save(self._job_id, self)


class IdempotencyConflict(ValueError):
    """An idempotency key was reused for a different canonical request."""


class JobRegistry(dict[str, dict[str, Any]]):
    """Dict-compatible registry that persists every job state transition."""

    ACTIVE_STATES = {"queued", "rendering"}

    def __init__(self, database: str | Path):
        super().__init__()
        self.database = Path(database)
        self.database.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            os.chmod(self.database.parent, 0o700)
        except OSError:
            pass
        with self._connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS media_jobs (
                    job_id TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    updated_at REAL NOT NULL
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS render_idempotency (
                    scope TEXT NOT NULL,
                    idempotency_key TEXT NOT NULL,
                    fingerprint TEXT NOT NULL,
                    job_id TEXT NOT NULL UNIQUE,
                    created_at REAL NOT NULL,
                    PRIMARY KEY(scope, idempotency_key)
                )
                """
            )
            legacy_rows = connection.execute(
                "SELECT job_id, payload, updated_at FROM media_jobs ORDER BY updated_at"
            ).fetchall()
            # Migrate keys written by the earlier process-local implementation
            # so deployment does not forget previously accepted requests.
            for legacy_job_id, legacy_payload, updated_at in legacy_rows:
                try:
                    legacy_values = json.loads(legacy_payload)
                except (TypeError, ValueError):
                    continue
                if not isinstance(legacy_values, dict):
                    continue
                scope = legacy_values.get("_idempotency_scope")
                key = legacy_values.get("_idempotency_key")
                fingerprint = legacy_values.get("_request_fingerprint")
                if all(isinstance(value, str) and value for value in (scope, key, fingerprint)):
                    connection.execute(
                        """INSERT OR IGNORE INTO render_idempotency(
                               scope, idempotency_key, fingerprint, job_id, created_at
                           ) VALUES (?, ?, ?, ?, ?)""",
                        (scope, key, fingerprint, legacy_job_id, updated_at),
                    )
            rows = [(job_id, payload) for job_id, payload, _ in legacy_rows]
        # SQLite creates the database using the process umask, which may be
        # more permissive than this service's private-media policy. Restrict it
        # immediately, including on first startup before any job is written.
        self._restrict_database_permissions()
        for job_id, payload in rows:
            try:
                values = json.loads(payload)
                if not isinstance(values, dict):
                    continue
            except (TypeError, ValueError):
                continue
            record = _PersistentJob(job_id, values, self)
            dict.__setitem__(self, job_id, record)
        # A process restart destroys daemon workers and cancellation events.
        # Never report an orphaned active job as still running.
        for job_id, record in list(self.items()):
            if record.get("state") in self.ACTIVE_STATES:
                record.update(
                    state="failed",
                    progress=0.0,
                    message="Elaborazione interrotta dal riavvio del server. Ripeti l'operazione.",
                    error="worker_interrupted",
                )

    def _restrict_database_permissions(self) -> None:
        try:
            os.chmod(self.database, 0o600)
        except OSError:
            # Some filesystems do not expose POSIX permission bits.
            pass

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database, timeout=10)
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def get(self, job_id: str, default: Any = None) -> Any:
        """Refresh a job snapshot from SQLite before returning it.

        This lets a process observe state transitions persisted by another
        registry instance. Worker execution and cancellation events remain
        process-local; this is not a distributed worker queue.
        """
        with self._connection() as connection:
            row = connection.execute(
                "SELECT payload FROM media_jobs WHERE job_id = ?", (job_id,)
            ).fetchone()
        if row is None:
            return dict.get(self, job_id, default)
        try:
            values = json.loads(row[0])
            if not isinstance(values, dict):
                return dict.get(self, job_id, default)
        except (TypeError, ValueError):
            return dict.get(self, job_id, default)
        record = _PersistentJob(job_id, values, self)
        dict.__setitem__(self, job_id, record)
        return record

    def _save(self, job_id: str, values: dict[str, Any]) -> None:
        payload = json.dumps(values, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        with self._connection() as connection:
            connection.execute(
                """
                INSERT INTO media_jobs(job_id, payload, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(job_id) DO UPDATE SET
                    payload=excluded.payload,
                    updated_at=excluded.updated_at
                """,
                (job_id, payload, time.time()),
            )
        self._restrict_database_permissions()

    def create_idempotent_job(
        self,
        job_id: str,
        values: dict[str, Any],
        scope: str,
        idempotency_key: str,
        fingerprint: str,
    ) -> tuple[str, bool]:
        """Atomically reserve an idempotency key and persist its job in SQLite.

        The unique (scope, key) constraint and BEGIN IMMEDIATE make this safe
        across concurrent registry instances sharing the same SQLite database.
        Returns (canonical_job_id, created); raises IdempotencyConflict when
        the key was already reserved for a different request fingerprint.
        """
        payload_values = dict(values)
        payload = json.dumps(
            payload_values, ensure_ascii=False, separators=(",", ":"), allow_nan=False
        )
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                """SELECT job_id, fingerprint FROM render_idempotency
                   WHERE scope=? AND idempotency_key=?""",
                (scope, idempotency_key),
            ).fetchone()
            if existing is not None:
                connection.rollback()
                existing_job_id, existing_fingerprint = existing
                if existing_fingerprint != fingerprint:
                    raise IdempotencyConflict(
                        "Idempotency key was reused with a different request."
                    )
                return existing_job_id, False
            connection.execute(
                """INSERT INTO media_jobs(job_id, payload, updated_at)
                   VALUES (?, ?, ?)""",
                (job_id, payload, time.time()),
            )
            connection.execute(
                """INSERT INTO render_idempotency(
                       scope, idempotency_key, fingerprint, job_id, created_at
                   ) VALUES (?, ?, ?, ?, ?)""",
                (scope, idempotency_key, fingerprint, job_id, time.time()),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
        dict.__setitem__(self, job_id, _PersistentJob(job_id, payload_values, self))
        self._restrict_database_permissions()
        return job_id, True

    def __setitem__(self, job_id: str, values: dict[str, Any]) -> None:
        record = _PersistentJob(job_id, dict(values), self)
        dict.__setitem__(self, job_id, record)
        self._save(job_id, record)

    def pop(self, job_id: str, *default: Any) -> Any:
        value = dict.pop(self, job_id, *default)
        with self._connection() as connection:
            connection.execute("DELETE FROM media_jobs WHERE job_id = ?", (job_id,))
            connection.execute("DELETE FROM render_idempotency WHERE job_id = ?", (job_id,))
        return value

    def clear(self) -> None:
        dict.clear(self)
        with self._connection() as connection:
            connection.execute("DELETE FROM media_jobs")
            connection.execute("DELETE FROM render_idempotency")
