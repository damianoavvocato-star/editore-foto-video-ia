"""Server-side adapter for the official Synthesia Video API (Legacy v2).

Only script/avatar video creation and status retrieval are supported here.
The adapter is intentionally not wired to public job routes until account-level
billing, consent, quota and durable worker orchestration are in place.
"""
from __future__ import annotations

import re
from typing import Any

import httpx

from backend.studio import StudioJobRequest


SYNTHESIA_API_BASE_URL = "https://api.synthesia.io/v2"
VIDEO_ID_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


class SynthesiaProviderError(RuntimeError):
    """A provider is unavailable or returned an invalid response."""


class SynthesiaVideoProvider:
    """Small, testable HTTP adapter; credentials remain server-side only."""

    def __init__(
        self,
        api_key: str | None = None,
        avatar_id: str | None = None,
        background: str = "off_white",
        test_mode: bool = True,
        timeout_seconds: float = 20.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self._api_key = (api_key or "").strip()
        self._avatar_id = (avatar_id or "").strip()
        self._background = background.strip() or "off_white"
        self._test_mode = test_mode
        self._timeout_seconds = max(1.0, min(timeout_seconds, 60.0))
        self._transport = transport

    @property
    def configured(self) -> bool:
        return bool(self._api_key and self._avatar_id)

    def _client(self) -> httpx.Client:
        if not self.configured:
            raise SynthesiaProviderError(
                "Synthesia non configurato: servono API key e avatar predefinito."
            )
        return httpx.Client(
            base_url=SYNTHESIA_API_BASE_URL,
            headers={
                "Authorization": self._api_key,
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            timeout=self._timeout_seconds,
            transport=self._transport,
        )

    def create_video(
        self, request: StudioJobRequest, callback_id: str | None = None
    ) -> dict[str, Any]:
        """Submit a private script-based video and return its provider metadata."""
        if request.task not in {"script_to_video", "avatar_video"}:
            raise SynthesiaProviderError(
                "Il provider configurato supporta per ora solo video da script/avatar."
            )
        script = request.script.strip()
        if not script:
            raise SynthesiaProviderError("Lo script del video non può essere vuoto.")
        if callback_id is not None and (
            not callback_id.strip() or len(callback_id) > 255
        ):
            raise SynthesiaProviderError("Callback ID non valido.")

        payload: dict[str, Any] = {
            "title": request.title,
            "input": [{
                "scriptText": script,
                "avatar": self._avatar_id,
                "background": self._background,
            }],
            "visibility": "private",
            "test": self._test_mode,
        }
        if callback_id:
            payload["callbackId"] = callback_id

        try:
            with self._client() as client:
                response = client.post("/videos", json=payload)
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SynthesiaProviderError("Errore durante la creazione del video Synthesia.") from exc

        if not isinstance(data, dict) or not isinstance(data.get("id"), str):
            raise SynthesiaProviderError("Risposta Synthesia priva di un ID video valido.")
        return {
            "provider": "synthesia",
            "providerVideoId": data["id"],
            "providerStatus": data.get("status", "in_progress"),
            "title": data.get("title", request.title),
            "visibility": data.get("visibility", "private"),
            "test": data.get("test", self._test_mode),
        }

    def retrieve_video(self, video_id: str) -> dict[str, Any]:
        """Retrieve provider status; download URLs are returned only by Synthesia."""
        if not VIDEO_ID_PATTERN.fullmatch(video_id or ""):
            raise SynthesiaProviderError("ID video Synthesia non valido.")
        try:
            with self._client() as client:
                response = client.get(f"/videos/{video_id}")
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SynthesiaProviderError("Errore durante il recupero del video Synthesia.") from exc

        if not isinstance(data, dict) or data.get("id") != video_id:
            raise SynthesiaProviderError("Risposta Synthesia non coerente con il video richiesto.")
        return {
            "provider": "synthesia",
            "providerVideoId": video_id,
            "providerStatus": data.get("status", "unknown"),
            "downloadUrl": data.get("download"),
            "duration": data.get("duration"),
            "captions": data.get("captions"),
        }
