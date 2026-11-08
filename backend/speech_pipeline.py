"""Provider-neutral speech pipeline contracts for transcription and localization.

This module validates AI-produced speech data and prepares subtitle files.
It deliberately performs no network requests and generates no synthetic voice:
a configured, reviewed provider adapter must be injected by the deployment.
"""
from __future__ import annotations

import html
import re
from dataclasses import dataclass
from typing import Any, Protocol

MAX_TRANSCRIPT_SEGMENTS = 2_000
MAX_TRANSCRIPT_DURATION_MS = 24 * 60 * 60 * 1000
MAX_SEGMENT_TEXT_CHARS = 4_000
_SUPPORTED_LANGUAGES = {
    "it", "en", "fr", "es", "ar", "de", "pt", "zh", "ja", "hi", "ru",
    "ko", "nl", "tr", "pl", "uk", "id", "vi", "th", "sv", "da", "no",
    "fi", "el", "he", "cs", "ro", "hu", "bn", "ur",
}
_LANGUAGE_RE = re.compile(r"^[a-z]{2,3}(?:-[A-Za-z]{2}|-[A-Z][a-z]{3})?$")
_SEGMENT_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")


class SpeechPipelineError(ValueError):
    """Safe validation or configuration error for speech workflows."""


class SpeechProviderNotConfigured(RuntimeError):
    """Raised when a speech operation is requested without a real provider."""


@dataclass(frozen=True)
class SpeechSegment:
    segment_id: str
    start_ms: int
    end_ms: int
    text: str
    speaker_id: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "segmentId": self.segment_id,
            "startMs": self.start_ms,
            "endMs": self.end_ms,
            "text": self.text,
            "speakerId": self.speaker_id,
        }


class SpeechProvider(Protocol):
    """Deployment adapter contract; implementations keep credentials server-side."""

    def transcribe(self, asset_path: str, language: str | None = None) -> Any: ...
    def translate(self, segments: list[dict[str, Any]], target_language: str) -> Any: ...


def normalise_language(language: Any) -> str:
    if not isinstance(language, str):
        raise SpeechPipelineError("Codice lingua non valido.")
    value = language.strip()
    if not _LANGUAGE_RE.fullmatch(value):
        raise SpeechPipelineError("Codice lingua non valido.")
    base = value.split("-", 1)[0].lower()
    if base not in _SUPPORTED_LANGUAGES:
        raise SpeechPipelineError("Lingua non supportata.")
    if "-" not in value:
        return base
    suffix = value.split("-", 1)[1]
    return f"{base}-{suffix.upper() if len(suffix) == 2 else suffix.title()}"


def _strict_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise SpeechPipelineError(f"Campo {field} non valido.")
    return value


def normalise_transcript(raw: Any, duration_ms: int) -> list[SpeechSegment]:
    duration = _strict_int(duration_ms, "durationMs")
    if not 1 <= duration <= MAX_TRANSCRIPT_DURATION_MS:
        raise SpeechPipelineError("Durata audio/video fuori dai limiti consentiti.")
    if not isinstance(raw, dict) or not isinstance(raw.get("segments"), list):
        raise SpeechPipelineError("Trascrizione non valida.")
    items = raw["segments"]
    if not items or len(items) > MAX_TRANSCRIPT_SEGMENTS:
        raise SpeechPipelineError("Numero di segmenti della trascrizione non valido.")

    segments: list[SpeechSegment] = []
    seen: set[str] = set()
    previous_start = -1
    for item in items:
        if not isinstance(item, dict):
            raise SpeechPipelineError("Segmento della trascrizione non valido.")
        segment_id = item.get("segmentId")
        if not isinstance(segment_id, str) or not _SEGMENT_ID_RE.fullmatch(segment_id):
            raise SpeechPipelineError("Identificativo segmento non valido.")
        if segment_id in seen:
            raise SpeechPipelineError("Identificativo segmento duplicato.")
        start = _strict_int(item.get("startMs"), "startMs")
        end = _strict_int(item.get("endMs"), "endMs")
        text = item.get("text")
        if not isinstance(text, str) or not text.strip() or len(text) > MAX_SEGMENT_TEXT_CHARS:
            raise SpeechPipelineError("Testo del segmento vuoto o troppo lungo.")
        if start < 0 or end <= start or end > duration:
            raise SpeechPipelineError("Intervallo temporale del segmento non valido.")
        if start < previous_start:
            raise SpeechPipelineError("I segmenti devono essere ordinati per tempo.")
        speaker = item.get("speakerId")
        if speaker is not None and (
            not isinstance(speaker, str) or not _SEGMENT_ID_RE.fullmatch(speaker)
        ):
            raise SpeechPipelineError("Identificativo speaker non valido.")
        segments.append(SpeechSegment(segment_id, start, end, text.strip(), speaker))
        seen.add(segment_id)
        previous_start = start
    return segments


def normalise_translation(
    source_segments: list[SpeechSegment], raw: Any, target_language: str,
) -> list[SpeechSegment]:
    """Accept translated text only; source IDs and timings remain authoritative."""
    normalise_language(target_language)
    if not isinstance(raw, dict) or not isinstance(raw.get("segments"), list):
        raise SpeechPipelineError("Traduzione non valida.")
    translated = raw["segments"]
    if len(translated) != len(source_segments):
        raise SpeechPipelineError("La traduzione deve contenere tutti i segmenti originali.")
    by_id: dict[str, str] = {}
    for item in translated:
        if not isinstance(item, dict):
            raise SpeechPipelineError("Segmento tradotto non valido.")
        segment_id, text = item.get("segmentId"), item.get("text")
        if not isinstance(segment_id, str) or segment_id in by_id:
            raise SpeechPipelineError("Identificativo tradotto mancante o duplicato.")
        if not isinstance(text, str) or not text.strip() or len(text) > MAX_SEGMENT_TEXT_CHARS:
            raise SpeechPipelineError("Testo tradotto vuoto o troppo lungo.")
        by_id[segment_id] = text.strip()
    expected = {segment.segment_id for segment in source_segments}
    if set(by_id) != expected:
        raise SpeechPipelineError("La traduzione contiene segmenti mancanti o sconosciuti.")
    return [
        SpeechSegment(s.segment_id, s.start_ms, s.end_ms, by_id[s.segment_id], s.speaker_id)
        for s in source_segments
    ]


def _timestamp(milliseconds: int, decimal_separator: str) -> str:
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, millis = divmod(remainder, 1_000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}{decimal_separator}{millis:03d}"


def render_subtitles(segments: list[SpeechSegment], format: str = "srt") -> str:
    """Render validated segments as SRT or WebVTT without changing their timing."""
    kind = format.strip().lower() if isinstance(format, str) else ""
    if kind not in {"srt", "vtt"}:
        raise SpeechPipelineError("Formato sottotitoli non supportato.")
    if not segments or len(segments) > MAX_TRANSCRIPT_SEGMENTS:
        raise SpeechPipelineError("Nessun segmento valido da esportare.")
    blocks: list[str] = []
    for index, segment in enumerate(segments, start=1):
        if segment.start_ms < 0 or segment.end_ms <= segment.start_ms:
            raise SpeechPipelineError("Intervallo temporale non valido.")
        start = _timestamp(segment.start_ms, "." if kind == "vtt" else ",")
        end = _timestamp(segment.end_ms, "." if kind == "vtt" else ",")
        safe_text = html.escape(segment.text, quote=False).replace("--&gt;", "—&gt;")
        prefix = f"{index}\n" if kind == "srt" else ""
        blocks.append(f"{prefix}{start} --> {end}\n{safe_text}")
    return ("WEBVTT\n\n" if kind == "vtt" else "") + "\n\n".join(blocks) + "\n"


class SpeechPipeline:
    """Thin fail-closed orchestration facade around an injected speech provider."""

    def __init__(self, provider: SpeechProvider | None = None):
        self._provider = provider

    @property
    def configured(self) -> bool:
        return self._provider is not None

    def transcribe(self, asset_path: str, duration_ms: int, language: str | None = None) -> list[SpeechSegment]:
        if self._provider is None:
            raise SpeechProviderNotConfigured("Provider di trascrizione non configurato.")
        if not isinstance(asset_path, str) or not asset_path.strip():
            raise SpeechPipelineError("File audio/video non valido.")
        language_hint = normalise_language(language) if language is not None else None
        raw = self._provider.transcribe(asset_path, language_hint)
        return normalise_transcript(raw, duration_ms)

    def translate(self, segments: list[SpeechSegment], target_language: str) -> list[SpeechSegment]:
        if self._provider is None:
            raise SpeechProviderNotConfigured("Provider di traduzione non configurato.")
        language = normalise_language(target_language)
        if not segments:
            raise SpeechPipelineError("Nessun segmento da tradurre.")
        raw = self._provider.translate(
            [segment.to_dict() for segment in segments], language
        )
        return normalise_translation(segments, raw, language)
