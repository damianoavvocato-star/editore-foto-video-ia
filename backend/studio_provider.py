"""Server-side adapter for the official Synthesia Video API (Legacy v2).

Only script/avatar and template-based video creation are supported here.
The adapter is intentionally not wired to public job routes until account-level
billing, consent, quota and durable worker orchestration are in place.
"""
from __future__ import annotations

import os
import re
from typing import Any, Mapping
from uuid import UUID

import httpx

from backend.studio import StudioJobRequest


SYNTHESIA_API_BASE_URL = "https://api.synthesia.io/v2"
VIDEO_ID_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
VIDEO_STATUSES = {"in_progress", "complete", "error", "rejected"}


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

    @classmethod
    def from_environment(
        cls,
        environ: Mapping[str, str] | None = None,
        transport: httpx.BaseTransport | None = None,
    ) -> "SynthesiaVideoProvider":
        """Load credentials from server environment; paid mode is opt-in."""
        env = os.environ if environ is None else environ
        api_key = env.get("SYNTHESIA_API_KEY", "")
        avatar_id = env.get("SYNTHESIA_DEFAULT_AVATAR_ID", "")
        raw_test_mode = env.get("SYNTHESIA_TEST_MODE", "true").strip().lower()
        if raw_test_mode not in {"true", "false"}:
            raise SynthesiaProviderError(
                "SYNTHESIA_TEST_MODE deve essere true oppure false."
            )
        test_mode = raw_test_mode == "true"
        if not test_mode and env.get("SYNTHESIA_ALLOW_PAID_GENERATION", "").lower() != "true":
            raise SynthesiaProviderError(
                "La generazione a pagamento richiede SYNTHESIA_ALLOW_PAID_GENERATION=true."
            )
        return cls(
            api_key=api_key,
            avatar_id=avatar_id,
            test_mode=test_mode,
            transport=transport,
        )

    @property
    def configured(self) -> bool:
        return bool(self._api_key and self._avatar_id)

    @property
    def test_mode(self) -> bool:
        return self._test_mode

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

    @staticmethod
    def _video_metadata(data: Any, fallback_title: str) -> dict[str, Any]:
        if not isinstance(data, dict) or not isinstance(data.get("id"), str):
            raise SynthesiaProviderError(
                "Risposta Synthesia priva di un ID video valido."
            )
        if not VIDEO_ID_PATTERN.fullmatch(data["id"]):
            raise SynthesiaProviderError(
                "Synthesia ha restituito un ID video non valido."
            )
        status = data.get("status", "in_progress")
        if status not in VIDEO_STATUSES:
            raise SynthesiaProviderError(
                "Synthesia ha restituito uno stato video sconosciuto."
            )
        return {
            "provider": "synthesia",
            "providerVideoId": data["id"],
            "providerStatus": status,
            "title": data.get("title", fallback_title),
            "visibility": data.get("visibility", "private"),
            "test": data.get("test", True),
        }

    def create_video(
        self, request: StudioJobRequest, callback_id: str | None = None
    ) -> dict[str, Any]:
        """Submit a supported script or template request to Synthesia."""
        if callback_id is not None and (
            not callback_id.strip() or len(callback_id) > 255
        ):
            raise SynthesiaProviderError("Callback ID non valido.")

        if request.task in {"script_to_video", "avatar_video"}:
            script = request.script.strip()
            if not script:
                raise SynthesiaProviderError("Lo script del video non può essere vuoto.")
            endpoint = "/videos"
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
        elif request.task == "bulk_personalization":
            try:
                template_id = str(UUID(request.templateId or ""))
            except (ValueError, TypeError, AttributeError) as exc:
                raise SynthesiaProviderError(
                    "Per la personalizzazione massiva serve un template ID UUID valido."
                ) from exc
            if not request.variables:
                raise SynthesiaProviderError(
                    "Inserisci almeno una variabile per il template."
                )
            endpoint = "/videos/fromTemplate"
            payload = {
                "title": request.title,
                "templateId": template_id,
                "templateData": request.variables,
                "visibility": "private",
                "test": self._test_mode,
            }
        else:
            raise SynthesiaProviderError(
                "Il provider supporta per ora video da script/avatar e template."
            )

        if callback_id:
            payload["callbackId"] = callback_id

        try:
            with self._client() as client:
                response = client.post(endpoint, json=payload)
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SynthesiaProviderError(
                "Errore durante la creazione del video Synthesia."
            ) from exc
        return self._video_metadata(data, request.title)

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
            raise SynthesiaProviderError(
                "Errore durante il recupero del video Synthesia."
            ) from exc

        if not isinstance(data, dict) or data.get("id") != video_id:
            raise SynthesiaProviderError(
                "Risposta Synthesia non coerente con il video richiesto."
            )
        status = data.get("status", "unknown")
        if status not in VIDEO_STATUSES:
            raise SynthesiaProviderError(
                "Synthesia ha restituito uno stato video sconosciuto."
            )
        return {
            "provider": "synthesia",
            "providerVideoId": video_id,
            "providerStatus": status,
            "downloadUrl": data.get("download"),
            "duration": data.get("duration"),
            "captions": data.get("captions"),
        }
