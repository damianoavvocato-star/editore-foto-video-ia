"""Provider-neutral Synthesia Studio job contracts and private draft storage.

This module stores reviewed generation requests only. It deliberately does not
pretend to generate video until a real, licensed provider adapter is configured.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, Field, validator


STUDIO_TASKS = {
    "script_to_video",
    "document_to_video",
    "slides_to_video",
    "avatar_video",
    "talking_photo",
    "translate_dub",
    "interactive_video",
    "bulk_personalization",
    "screen_explainer",
}
LANGUAGE_PATTERN = re.compile(r"^[a-z]{2,3}(?:-[A-Z]{2})?$")
ASSET_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
SUPPORTED_DOCUMENT_EXTENSIONS = {
    ".pdf", ".docx", ".pptx", ".txt", ".md", ".rtf",
}


class StudioRequestError(ValueError):
    """A studio request is invalid or conflicts with an earlier draft."""


class StudioJobRequest(BaseModel):
    task: Literal[
        "script_to_video", "document_to_video", "slides_to_video",
        "avatar_video", "talking_photo", "translate_dub",
        "interactive_video", "bulk_personalization", "screen_explainer",
    ]
    title: str = Field(default="Nuovo video IA", min_length=1, max_length=120)
    script: str = Field(default="", max_length=30000)
    sourceAssetIds: list[str] = Field(default_factory=list, max_length=20)
    sourceLanguage: str | None = Field(default=None, max_length=8)
    targetLanguages: list[str] = Field(default_factory=lambda: ["it-IT"], max_length=20)
    avatarMode: Literal["stock", "generated", "personal", "none"] = "none"
    avatarConsent: bool = False
    voiceMode: Literal["synthetic", "licensed", "clone"] = "synthetic"
    voiceConsent: bool = False
    interactive: bool = False
    templateId: str | None = Field(default=None, max_length=80)
    variables: dict[str, str] = Field(default_factory=dict)

    @validator("title")
    def clean_title(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Il titolo non può essere vuoto.")
        return value

    @validator("sourceLanguage")
    def valid_source_language(cls, value: str | None) -> str | None:
        if value is not None and not LANGUAGE_PATTERN.fullmatch(value):
            raise ValueError("Codice lingua sorgente non valido.")
        return value

    @validator("targetLanguages")
    def valid_target_languages(cls, values: list[str]) -> list[str]:
        if not values or len(values) > 20:
            raise ValueError("Seleziona da 1 a 20 lingue di destinazione.")
        if any(not isinstance(value, str) or not LANGUAGE_PATTERN.fullmatch(value) for value in values):
            raise ValueError("Uno o più codici lingua non sono validi.")
        if len(set(values)) != len(values):
            raise ValueError("Le lingue di destinazione non possono essere duplicate.")
        return values

    @validator("sourceAssetIds")
    def valid_source_assets(cls, values: list[str]) -> list[str]:
        if len(values) > 20 or any(
            not isinstance(value, str) or not ASSET_ID_PATTERN.fullmatch(value)
            for value in values
        ):
            raise ValueError("Selezione media non valida: massimo 20 elementi.")
        if len(set(values)) != len(values):
            raise ValueError("La selezione contiene media duplicati.")
        return values

    @validator("variables")
    def bounded_variables(cls, values: dict[str, str]) -> dict[str, str]:
        if len(values) > 100:
            raise ValueError("Sono ammesse al massimo 100 variabili per modello.")
        for key, value in values.items():
            if not key.strip() or len(key) > 80 or len(value) > 2000:
                raise ValueError("Variabile del modello non valida o troppo lunga.")
        return values

    def validate_policy(self) -> None:
        if self.sourceLanguage and self.sourceLanguage in self.targetLanguages:
            raise StudioRequestError("La lingua sorgente non può essere anche una destinazione.")
        if self.avatarMode == "personal" and not self.avatarConsent:
            raise StudioRequestError("Per usare un avatar personale serve il consenso verificato.")
        if self.voiceMode == "clone" and not self.voiceConsent:
            raise StudioRequestError("Per clonare una voce serve il consenso verificato.")
        if self.task in {"document_to_video", "slides_to_video", "talking_photo", "translate_dub"} and not self.sourceAssetIds:
            raise StudioRequestError("Questa attività richiede almeno un file multimediale sorgente.")
        if self.task in {"script_to_video", "avatar_video"} and not self.script.strip() and not self.sourceAssetIds:
            raise StudioRequestError("Inserisci uno script o seleziona un contenuto sorgente.")
        if self.task == "interactive_video" and not self.interactive:
            raise StudioRequestError("Attiva l'opzione video interattivo per questo progetto.")


class StudioJobStore:
    """SQLite-backed, account-scoped storage for Studio generation drafts."""

    def __init__(self, database: str | Path):
        self.database = Path(database)
        self.database.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self._connect() as connection:
            connection.execute(
                """CREATE TABLE IF NOT EXISTS studio_jobs (
                    job_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    state TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    request_hash TEXT NOT NULL,
                    idempotency_key TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )"""
            )
            connection.execute(
                """CREATE UNIQUE INDEX IF NOT EXISTS studio_user_idempotency
                   ON studio_jobs(user_id, idempotency_key)
                   WHERE idempotency_key IS NOT NULL"""
            )
        self._restrict_permissions()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection

    def _restrict_permissions(self) -> None:
        try:
            os.chmod(self.database, 0o600)
            os.chmod(self.database.parent, 0o700)
        except OSError:
            pass

    def create_draft(
        self, user_id: str, request: StudioJobRequest, idempotency_key: str | None = None
    ) -> tuple[dict[str, Any], bool]:
        if not user_id:
            raise StudioRequestError("Account obbligatorio.")
        request.validate_policy()
        payload = request.dict()
        canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        now = time.time()
        job_id = uuid.uuid4().hex
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            if idempotency_key:
                existing = connection.execute(
                    "SELECT * FROM studio_jobs WHERE user_id=? AND idempotency_key=?",
                    (user_id, idempotency_key),
                ).fetchone()
                if existing:
                    if existing["request_hash"] != fingerprint:
                        raise StudioRequestError("Chiave idempotenza già usata per una richiesta differente.")
                    connection.rollback()
                    return self._row_to_dict(existing), False
            connection.execute(
                """INSERT INTO studio_jobs(
                    job_id, user_id, state, payload, request_hash,
                    idempotency_key, created_at, updated_at
                ) VALUES (?, ?, 'draft', ?, ?, ?, ?, ?)""",
                (job_id, user_id, canonical, fingerprint, idempotency_key, now, now),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
        self._restrict_permissions()
        return {
            "jobId": job_id, "state": "draft", "request": payload,
            "providerState": "not_configured", "createdAt": now, "updatedAt": now,
        }, True

    @staticmethod
    def _row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "jobId": row["job_id"], "state": row["state"],
            "request": json.loads(row["payload"]),
            "providerState": "not_configured",
            "createdAt": row["created_at"], "updatedAt": row["updated_at"],
        }

    def get(self, user_id: str, job_id: str) -> dict[str, Any] | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM studio_jobs WHERE user_id=? AND job_id=?",
                (user_id, job_id),
            ).fetchone()
        return self._row_to_dict(row) if row else None

    def list_for_user(self, user_id: str, limit: int = 50) -> list[dict[str, Any]]:
        limit = max(1, min(100, limit))
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM studio_jobs WHERE user_id=? ORDER BY created_at DESC LIMIT ?",
                (user_id, limit),
            ).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def delete_draft(self, user_id: str, job_id: str) -> bool:
        with self._connect() as connection:
            cursor = connection.execute(
                "DELETE FROM studio_jobs WHERE user_id=? AND job_id=? AND state='draft'",
                (user_id, job_id),
            )
            return cursor.rowcount == 1
