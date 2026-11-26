"""Safe MagicLink URL intake and platform classification.

This module deliberately does not fetch remote URLs. A future extractor must use
an isolated, SSRF-hardened fetch service and respect platform access controls.
"""
from __future__ import annotations

import ipaddress
from urllib.parse import urlsplit

from pydantic import BaseModel, Field, field_validator


PLATFORM_DOMAINS = {
    "tiktok": ("tiktok.com",),
    "youtube": ("youtube.com", "youtu.be"),
    "instagram": ("instagram.com",),
    "facebook": ("facebook.com", "fb.watch"),
    "x": ("x.com", "twitter.com"),
    "vimeo": ("vimeo.com",),
}


class MagicLinkRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2048)
    instruction: str | None = Field(default=None, max_length=1000)

    @field_validator("url")
    @classmethod
    def validate_public_http_url(cls, value: str) -> str:
        value = value.strip()
        try:
            parsed = urlsplit(value)
            host = parsed.hostname
            port = parsed.port
        except ValueError as exc:
            raise ValueError("Link non valido.") from exc
        if parsed.scheme.lower() not in {"http", "https"}:
            raise ValueError("Sono ammessi soltanto link HTTP o HTTPS.")
        if not host or parsed.username is not None or parsed.password is not None:
            raise ValueError("Il link deve avere un host pubblico e non contenere credenziali.")
        if port not in (None, 80, 443):
            raise ValueError("Le porte personalizzate non sono supportate.")
        host = host.rstrip(".").lower()
        if host == "localhost" or host.endswith((".localhost", ".local", ".internal", ".test")):
            raise ValueError("I link a host locali o interni non sono consentiti.")
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            try:
                ascii_host = host.encode("idna").decode("ascii")
            except UnicodeError as exc:
                raise ValueError("Nome host non valido.") from exc
            labels = ascii_host.split(".")
            if len(labels) < 2 or any(
                not label or len(label) > 63 or label.startswith("-")
                or label.endswith("-") or not all(ch.isalnum() or ch == "-" for ch in label)
                for label in labels
            ):
                raise ValueError("Nome host non valido.")
        else:
            if not address.is_global:
                raise ValueError("Gli indirizzi IP privati o riservati non sono consentiti.")
        return value


def classify_platform(url: str) -> str:
    host = (urlsplit(url).hostname or "").lower().rstrip(".")
    for platform, domains in PLATFORM_DOMAINS.items():
        if any(host == domain or host.endswith("." + domain) for domain in domains):
            return platform
    return "website"


def describe_link(request: MagicLinkRequest) -> dict:
    platform = classify_platform(request.url)
    return {
        "platform": platform,
        "submittedUrl": request.url,
        "instruction": request.instruction,
        "contentAccess": "not_fetched",
        "providerState": "not_configured",
        "availableNextSteps": [
            "import_authorized_media",
            "transcribe",
            "translate_subtitles",
            "dub_audio",
            "summarize",
            "edit_with_magiciaedit",
        ],
        "message": (
            "Il collegamento è stato riconosciuto, ma il contenuto remoto non è stato "
            "scaricato né analizzato. Importa un file che sei autorizzato a usare; "
            "l'estrazione dai siti richiederà un connettore compatibile e autorizzato."
        ),
    }
