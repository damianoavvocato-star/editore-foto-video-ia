"""Private object storage for completed Studio videos.

The adapter is deliberately not wired to public routes or workers yet. It
stores bytes under account-scoped keys, never grants public ACLs, and creates
short-lived HTTPS download URLs only after an ownership-scoped existence check.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Any, Mapping
from urllib.parse import urlparse


_ACCOUNT_ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
_JOB_ID = re.compile(r"^[0-9a-f]{32}$")
_CONTENT_TYPES = {
    "video/mp4": "mp4",
    "video/webm": "webm",
    "video/quicktime": "mov",
    "video/x-msvideo": "avi",
}


class VideoStorageError(RuntimeError):
    """Storage is unavailable or an object operation is invalid."""


@dataclass(frozen=True)
class StoredVideo:
    object_key: str
    content_type: str
    size_bytes: int


class S3PrivateVideoStorage:
    """S3-compatible private storage; credentials are server-side only."""

    def __init__(
        self,
        client: Any,
        bucket: str,
        *,
        max_video_bytes: int = 2_000_000_000,
        endpoint_url: str | None = None,
    ) -> None:
        if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket or ""):
            raise VideoStorageError("Nome bucket non valido.")
        if max_video_bytes < 1:
            raise VideoStorageError("Limite dimensione video non valido.")
        self._client = client
        self._bucket = bucket
        self._max_video_bytes = max_video_bytes
        self._endpoint_url = endpoint_url or getattr(
            getattr(client, "meta", None), "endpoint_url", None
        )

    @classmethod
    def from_environment(
        cls,
        environ: Mapping[str, str] | None = None,
        client: Any | None = None,
    ) -> "S3PrivateVideoStorage":
        """Build from server environment; return no fallback to public storage."""
        env = os.environ if environ is None else environ
        bucket = env.get("STUDIO_S3_BUCKET", "").strip()
        if not bucket:
            raise VideoStorageError("Storage Studio non configurato.")
        endpoint = env.get("STUDIO_S3_ENDPOINT_URL", "").strip() or None
        if endpoint:
            parsed = urlparse(endpoint)
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                raise VideoStorageError("Endpoint storage deve essere HTTPS e valido.")
            if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
                raise VideoStorageError("Endpoint storage non deve contenere path o query.")
        if client is None:
            try:
                import boto3
            except ImportError as exc:
                raise VideoStorageError("Dipendenza boto3 non disponibile.") from exc
            region = env.get("STUDIO_S3_REGION", "eu-west-1").strip()
            if not region:
                raise VideoStorageError("Regione storage non valida.")
            client = boto3.client(
                "s3",
                region_name=region,
                endpoint_url=endpoint,
                aws_access_key_id=env.get("STUDIO_S3_ACCESS_KEY_ID") or None,
                aws_secret_access_key=env.get("STUDIO_S3_SECRET_ACCESS_KEY") or None,
            )
        return cls(
            client,
            bucket,
            max_video_bytes=int(env.get("STUDIO_MAX_VIDEO_BYTES", "2000000000")),
            endpoint_url=endpoint,
        )

    @staticmethod
    def _object_key(user_id: str, job_id: str, extension: str) -> str:
        if not _ACCOUNT_ID.fullmatch(user_id or ""):
            raise VideoStorageError("Account non valido.")
        if not _JOB_ID.fullmatch(job_id or ""):
            raise VideoStorageError("Identificativo job non valido.")
        if extension not in set(_CONTENT_TYPES.values()):
            raise VideoStorageError("Formato video non supportato.")
        return f"users/{user_id}/studio/{job_id}/output.{extension}"

    def store_video(
        self, user_id: str, job_id: str, content: bytes, content_type: str
    ) -> StoredVideo:
        extension = _CONTENT_TYPES.get((content_type or "").lower())
        if extension is None:
            raise VideoStorageError("Tipo contenuto video non supportato.")
        if not isinstance(content, bytes) or not content:
            raise VideoStorageError("Video vuoto o contenuto non valido.")
        if len(content) > self._max_video_bytes:
            raise VideoStorageError("Video oltre il limite consentito.")
        key = self._object_key(user_id, job_id, extension)
        try:
            # No ACL is set: public-read is never requested. Bucket policy must
            # also block public access and enforce TLS at deployment level.
            self._client.put_object(
                Bucket=self._bucket,
                Key=key,
                Body=content,
                ContentType=content_type.lower(),
                ServerSideEncryption="AES256",
            )
        except Exception as exc:
            raise VideoStorageError("Salvataggio video privato non riuscito.") from exc
        return StoredVideo(key, content_type.lower(), len(content))

    def create_download_url(
        self, user_id: str, job_id: str, content_type: str, expires_seconds: int = 300
    ) -> str:
        extension = _CONTENT_TYPES.get((content_type or "").lower())
        if extension is None:
            raise VideoStorageError("Tipo contenuto video non supportato.")
        key = self._object_key(user_id, job_id, extension)
        if not 60 <= int(expires_seconds) <= 900:
            raise VideoStorageError("Scadenza link non valida.")
        try:
            self._client.head_object(Bucket=self._bucket, Key=key)
            url = self._client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self._bucket, "Key": key},
                ExpiresIn=int(expires_seconds),
            )
        except Exception as exc:
            raise VideoStorageError("Video privato non disponibile.") from exc
        parsed = urlparse(url)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise VideoStorageError("Il provider storage ha generato un link non sicuro.")
        return url

    def delete_video(self, user_id: str, job_id: str, content_type: str) -> None:
        extension = _CONTENT_TYPES.get((content_type or "").lower())
        if extension is None:
            raise VideoStorageError("Tipo contenuto video non supportato.")
        key = self._object_key(user_id, job_id, extension)
        try:
            self._client.delete_object(Bucket=self._bucket, Key=key)
        except Exception as exc:
            raise VideoStorageError("Eliminazione video privato non riuscita.") from exc
