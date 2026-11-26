"""Authenticated-asset speech job orchestration for MagicIAedit.

This module deliberately has no HTTP routes or provider credentials. A worker
must supply an account-ownership verifier and a configured speech adapter.
Artifacts are returned as data for a later account-scoped persistence stage.
"""
from __future__ import annotations

import re
import tempfile
from pathlib import Path
from typing import Any, Callable

from backend.media_audio import extract_audio_track
from backend.speech_pipeline import SpeechPipeline, normalise_language, render_subtitles

_ASSET_ID = re.compile(r"^[0-9a-f]{32}$")
MAX_TARGET_LANGUAGES = 20


class SpeechJobError(ValueError):
    """Invalid or unauthorized speech job input."""


def process_speech_job(
    *,
    user_id: str,
    asset_id: str,
    duration_ms: int,
    asset_root: str | Path,
    work_root: str | Path,
    authorize_asset: Callable[[str, str], bool],
    provider: Any,
    source_language: str | None = None,
    target_languages: list[str] | None = None,
    ffmpeg_bin: str = "ffmpeg",
) -> dict[str, Any]:
    """Transcribe one owned media asset and prepare source/translated subtitles.

    The caller must provide a verifier backed by the application's resource
    ownership store. Client-supplied filesystem paths are never accepted.
    Temporary extracted audio is removed on success and failure.
    """
    if not isinstance(user_id, str) or not user_id.strip() or len(user_id) > 256:
        raise SpeechJobError("Account non valido.")
    if not isinstance(asset_id, str) or not _ASSET_ID.fullmatch(asset_id):
        raise SpeechJobError("Identificativo media non valido.")
    if not callable(authorize_asset):
        raise SpeechJobError("Verifica proprietà media non configurata.")
    try:
        authorized = authorize_asset(user_id, asset_id) is True
    except Exception as exc:
        raise SpeechJobError("Impossibile verificare la proprietà del media.") from exc
    if not authorized:
        raise SpeechJobError("Media non autorizzato per questo account.")

    root = Path(asset_root)
    work = Path(work_root)
    if root.is_symlink() or work.is_symlink():
        raise SpeechJobError("Directory media non valida.")
    try:
        root = root.resolve(strict=True)
        work.mkdir(parents=True, exist_ok=True, mode=0o700)
        work = work.resolve(strict=True)
    except OSError as exc:
        raise SpeechJobError("Directory di lavoro non disponibile.") from exc
    if not root.is_dir() or not work.is_dir():
        raise SpeechJobError("Directory media non valida.")

    matches = list(root.glob(asset_id + ".*"))
    if len(matches) != 1:
        raise SpeechJobError("Media non trovato o ambiguo.")
    asset = matches[0]
    if asset.is_symlink():
        raise SpeechJobError("I collegamenti simbolici non sono consentiti.")
    try:
        asset = asset.resolve(strict=True)
    except OSError as exc:
        raise SpeechJobError("Media non disponibile.") from exc
    if asset.parent != root or not asset.is_file():
        raise SpeechJobError("Percorso media non valido.")

    if source_language is not None:
        source_language = normalise_language(source_language)
    if target_languages is None:
        target_languages = []
    if not isinstance(target_languages, list) or len(target_languages) > MAX_TARGET_LANGUAGES:
        raise SpeechJobError("Numero di lingue destinazione non valido.")
    targets = [normalise_language(language) for language in target_languages]
    if len(set(targets)) != len(targets):
        raise SpeechJobError("Le lingue destinazione non possono essere duplicate.")
    if source_language is not None and source_language in targets:
        raise SpeechJobError("La lingua sorgente non può essere anche destinazione.")

    pipeline = SpeechPipeline(provider)
    if not pipeline.configured:
        raise SpeechJobError("Provider di trascrizione non configurato.")

    with tempfile.TemporaryDirectory(prefix="speech-", dir=work) as temporary:
        audio_path = Path(temporary) / "source.wav"
        extract_audio_track(asset, audio_path, ffmpeg_bin=ffmpeg_bin)
        source_segments = pipeline.transcribe(
            str(audio_path), duration_ms, source_language
        )
        outputs: dict[str, dict[str, Any]] = {}

        def add_output(language_key: str, segments: list[Any]) -> None:
            outputs[language_key] = {
                "segments": [segment.to_dict() for segment in segments],
                "srt": render_subtitles(segments, "srt"),
                "vtt": render_subtitles(segments, "vtt"),
            }

        add_output(source_language or "auto", source_segments)
        for target in targets:
            translated = pipeline.translate(source_segments, target)
            add_output(target, translated)

    return {
        "assetId": asset_id,
        "sourceLanguage": source_language or "auto",
        "languages": outputs,
        "temporaryAudioRemoved": not audio_path.exists(),
    }
