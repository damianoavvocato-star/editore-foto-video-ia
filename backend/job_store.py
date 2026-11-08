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
            rows = connection.execute(
                "SELECT job_id, payload FROM media_jobs"
            ).fetchall()
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

    def __setitem__(self, job_id: str, values: dict[str, Any]) -> None:
        record = _PersistentJob(job_id, dict(values), self)
        dict.__setitem__(self, job_id, record)
        self._save(job_id, record)

    def pop(self, job_id: str, *default: Any) -> Any:
        value = dict.pop(self, job_id, *default)
        with self._connection() as connection:
            connection.execute("DELETE FROM media_jobs WHERE job_id = ?", (job_id,))
        return value

    def clear(self) -> None:
        dict.clear(self)
        with self._connection() as connection:
            connection.execute("DELETE FROM media_jobs")
