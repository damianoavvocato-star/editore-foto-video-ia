"""Cloud-backed MagicIAedit planning provider.

The provider uses an OpenAI-compatible vision chat-completions endpoint configured
only through server environment variables. No API key is ever sent to clients.
"""
from __future__ import annotations

import base64
import json
import math
import os
import subprocess
import tempfile
import urllib.error
import urllib.request
import warnings
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image

MAX_MEDIA = 20
MAX_PLAN_CLIPS = 24
MAX_IMAGE_BYTES = 4 * 1024 * 1024
MAX_IMAGE_ASSET_BYTES = 20 * 1024 * 1024
MAX_ASSET_BYTES = 100 * 1024 * 1024
MAX_TOTAL_ASSET_BYTES = 400 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 25_000_000
ALLOWED_TRANSITIONS = {
    "fade", "wipeleft", "wiperight", "slideleft", "slideright",
    "circleopen", "circleclose", "dissolve",
}


class MagicIAError(RuntimeError):
    """Safe, user-displayable MagicIAedit failure."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Reject provider redirects so Authorization cannot reach another host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def provider_configured() -> bool:
    base_url = os.getenv("MAGICIA_API_BASE_URL", "").strip()
    return (
        bool(os.getenv("MAGICIA_API_KEY", "").strip())
        and bool(os.getenv("MAGICIA_MODEL", "").strip())
        and base_url.startswith("https://")
    )


def _image_data_url(image: Image.Image) -> str:
    image = image.convert("RGB")
    image.thumbnail((1024, 1024))
    output = BytesIO()
    image.save(output, format="JPEG", quality=82, optimize=True)
    raw = output.getvalue()
    if len(raw) > MAX_IMAGE_BYTES:
        raise MagicIAError("Immagine troppo grande per l'analisi IA.")
    return "data:image/jpeg;base64," + base64.b64encode(raw).decode("ascii")


def _frame_timestamps(duration: float, max_frames: int = 8) -> list[float]:
    """Return evenly distributed frame times, including the opening and ending."""
    if not math.isfinite(duration) or duration <= 0:
        raise MagicIAError("Durata video non valida.")
    if max_frames < 2 or max_frames > 12:
        raise MagicIAError("Numero di fotogrammi di analisi non valido.")
    usable_end = max(0.0, duration - 0.05)
    if usable_end <= 0:
        return [0.0]
    count = min(max_frames, max(2, int(math.ceil(duration / 2.5)) + 1))
    return [round(usable_end * index / (count - 1), 3) for index in range(count)]


def _visual_quality_signals(image: Image.Image) -> dict[str, float]:
    """Compute lightweight, privacy-preserving visual signals for AI context."""
    from PIL import ImageFilter
    sample = image.convert("L")
    sample.thumbnail((256, 256))
    pixels = list(sample.getdata())
    if not pixels:
        return {"brightness": 0.0, "contrast": 0.0, "detail": 0.0}
    brightness = sum(pixels) / len(pixels) / 255.0
    variance = sum((pixel / 255.0 - brightness) ** 2 for pixel in pixels) / len(pixels)
    edge_pixels = list(sample.filter(ImageFilter.FIND_EDGES).getdata())
    detail = sum(edge_pixels) / len(edge_pixels) / 255.0 if edge_pixels else 0.0
    return {
        "brightness": round(brightness, 3),
        "contrast": round(math.sqrt(variance), 3),
        "detail": round(detail, 3),
    }


def _video_frames(path: Path, cancel_event: Any = None) -> list[tuple[float, Image.Image]]:
    if cancel_event is not None and cancel_event.is_set():
        raise MagicIAError("Elaborazione annullata.")
    ffmpeg = os.getenv("FFMPEG_PATH", "ffmpeg")
    ffprobe = os.getenv("FFPROBE_PATH", "ffprobe")
    try:
        probe = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise MagicIAError("Lettura della durata video non riuscita.") from exc
    if probe.returncode:
        raise MagicIAError("Impossibile leggere la durata di un video.")
    try:
        duration = float(probe.stdout.strip())
    except (TypeError, ValueError, OverflowError) as exc:
        raise MagicIAError("Durata video non valida.") from exc
    if not math.isfinite(duration) or duration <= 0 or duration > 86_400:
        raise MagicIAError("Durata video fuori dai limiti consentiti.")

    frames: list[tuple[float, Image.Image]] = []
    for timestamp in _frame_timestamps(duration):
        if cancel_event is not None and cancel_event.is_set():
            raise MagicIAError("Elaborazione annullata.")
        try:
            result = subprocess.run(
                [ffmpeg, "-v", "error", "-ss", f"{timestamp:.3f}", "-i", str(path),
                 "-frames:v", "1", "-vf", "scale=1024:1024:force_original_aspect_ratio=decrease",
                 "-f", "image2pipe", "-vcodec", "mjpeg", "-"],
                capture_output=True, timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise MagicIAError("Estrazione dei fotogrammi video non riuscita.") from exc
        if result.returncode or not result.stdout:
            continue
        try:
            with Image.open(BytesIO(result.stdout)) as frame:
                frames.append((timestamp, frame.copy()))
        except Exception:
            continue
    if not frames:
        raise MagicIAError("Non è stato possibile estrarre fotogrammi dal video.")
    return frames


def _media_parts(
    asset_paths: dict[str, Path], cancel_event: Any = None,
) -> list[dict[str, Any]]:
    parts: list[dict[str, Any]] = []
    for asset_id, path in asset_paths.items():
        if cancel_event is not None and cancel_event.is_set():
            raise MagicIAError("Elaborazione annullata.")
        suffix = path.suffix.lower()
        if suffix in {".jpg", ".jpeg", ".png", ".webp"}:
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("error", Image.DecompressionBombWarning)
                    with Image.open(path) as image:
                        parts.append({"type": "text", "text": f"Media assetId={asset_id}, tipo=immagine, segnali visivi={_visual_quality_signals(image)}."})
                        parts.append({"type": "image_url", "image_url": {"url": _image_data_url(image)}})
            except (OSError, ValueError, Image.DecompressionBombWarning, Image.DecompressionBombError) as exc:
                raise MagicIAError(f"Impossibile leggere l'immagine {asset_id}.") from exc
        elif suffix in {".mp4", ".mov", ".avi", ".webm", ".m4v"}:
            frames = _video_frames(path, cancel_event)
            parts.append({"type": "text", "text": f"Media assetId={asset_id}, tipo=video, {len(frames)} fotogrammi distribuiti lungo la durata e ordinati temporalmente."})
            for frame_number, (timestamp, frame) in enumerate(frames, start=1):
                signals = _visual_quality_signals(frame)
                parts.append({"type": "text", "text": f"Fotogramma {frame_number} del video {asset_id}, timestampMs={round(timestamp * 1000)}, segnali visivi={signals}."})
                parts.append({"type": "image_url", "image_url": {"url": _image_data_url(frame)}})
        else:
            raise MagicIAError("MagicIAedit supporta immagini e video, non file audio.")
    return parts


def _normalise_plan(raw: Any, asset_ids: set[str]) -> dict[str, Any]:
    if not isinstance(raw, dict) or not isinstance(raw.get("clips"), list):
        raise MagicIAError("Il modello IA ha restituito un piano non valido.")
    if not raw["clips"] or len(raw["clips"]) > MAX_PLAN_CLIPS:
        raise MagicIAError("Il piano IA non contiene un numero valido di clip.")

    clips = []
    cursor_ms = 0
    for item in raw["clips"]:
        if not isinstance(item, dict):
            raise MagicIAError("Una clip del piano IA non è valida.")
        asset_id = str(item.get("assetId", ""))
        if asset_id not in asset_ids:
            raise MagicIAError("Il piano IA contiene un media non selezionato.")
        try:
            source_start_value = int(item.get("sourceStartMs", 0))
            duration_value = int(item.get("durationMs", 3000))
            transition_value = int(item.get("transitionAfterMs", 0))
        except (TypeError, ValueError, OverflowError) as exc:
            raise MagicIAError("Il piano IA contiene tempi non validi.") from exc
        source_start = max(0, min(86_400_000, source_start_value))
        duration = max(500, min(20_000, duration_value))
        transition_ms = max(0, min(2000, transition_value, int(duration * 0.45)))
        transition = str(item.get("transitionAfter", "fade")).lower()
        if transition not in ALLOWED_TRANSITIONS:
            transition = "fade"
        clips.append({
            "assetId": asset_id,
            "sourceStartMs": source_start,
            "durationMs": duration,
            "startMs": cursor_ms,
            "transitionAfterMs": transition_ms,
            "transitionAfter": transition,
            "reason": str(item.get("reason", ""))[:240],
        })
        cursor_ms += max(1, duration - transition_ms)
    return {
        "title": str(raw.get("title", "Montaggio MagicIAedit"))[:100],
        "description": str(raw.get("description", ""))[:500],
        "durationMs": cursor_ms,
        "clips": clips,
    }



_STYLE_PRESETS = {"balanced", "cinematic", "travel", "family", "social_short", "product", "storytelling", "dynamic"}
_PACES = {"slow", "balanced", "fast"}
_ASPECT_RATIOS = {"9:16", "16:9", "1:1", "4:5"}
_LANGUAGES = {"it", "en", "fr", "es", "ar", "de", "pt", "zh", "ja", "hi", "ru", "ko", "nl", "tr", "pl", "uk", "id", "vi", "th", "sv", "da", "no", "fi", "el", "he", "cs", "ro", "hu", "bn", "ur"}


def _normalise_options(options: Any) -> dict[str, Any]:
    """Whitelist and bound user-controlled creative direction."""
    if options is None:
        options = {}
    if not isinstance(options, dict):
        raise MagicIAError("Le preferenze MagicIAedit non sono valide.")
    goal = options.get("goal", "")
    if not isinstance(goal, str):
        raise MagicIAError("La descrizione del montaggio deve essere testuale.")
    style = str(options.get("style", "balanced")).lower()
    pace = str(options.get("pace", "balanced")).lower()
    aspect_ratio = str(options.get("aspectRatio", "9:16"))
    language = str(options.get("language", "it")).lower()
    if style not in _STYLE_PRESETS or pace not in _PACES or aspect_ratio not in _ASPECT_RATIOS:
        raise MagicIAError("Una preferenza creativa MagicIAedit non è supportata.")
    if language not in _LANGUAGES:
        raise MagicIAError("Lingua MagicIAedit non supportata.")
    try:
        target_duration = int(options.get("targetDurationSeconds", 30))
    except (TypeError, ValueError, OverflowError) as exc:
        raise MagicIAError("Durata obiettivo MagicIAedit non valida.") from exc
    if not 5 <= target_duration <= 180:
        raise MagicIAError("La durata obiettivo deve essere compresa tra 5 e 180 secondi.")
    return {
        "goal": goal[:300],
        "style": style,
        "pace": pace,
        "aspectRatio": aspect_ratio,
        "language": language,
        "targetDurationSeconds": target_duration,
    }


def create_magic_plan(
    asset_paths: dict[str, Path],
    options: dict[str, Any] | None = None,
    cancel_event: Any = None,
) -> dict[str, Any]:
    if not provider_configured():
        raise MagicIAError("Provider cloud non configurato: MagicIAedit non è ancora attivo.")
    if not asset_paths or len(asset_paths) > MAX_MEDIA:
        raise MagicIAError(f"Seleziona da 1 a {MAX_MEDIA} foto o video.")
    total_bytes = 0
    for asset_id, path in asset_paths.items():
        try:
            asset_bytes = path.stat().st_size
        except OSError as exc:
            raise MagicIAError(f"Impossibile accedere al media {asset_id}.") from exc
        suffix = path.suffix.lower()
        if suffix in {".jpg", ".jpeg", ".png", ".webp"}:
            if asset_bytes <= 0 or asset_bytes > MAX_IMAGE_ASSET_BYTES:
                raise MagicIAError("Ogni immagine per MagicIAedit deve essere inferiore a 20 MB.")
        elif suffix in {".mp4", ".mov", ".avi", ".webm", ".m4v"}:
            if asset_bytes <= 0 or asset_bytes > MAX_ASSET_BYTES:
                raise MagicIAError("Ogni video per MagicIAedit deve essere inferiore a 100 MB.")
        else:
            raise MagicIAError("Formato media non supportato da MagicIAedit.")
        total_bytes += asset_bytes
    if total_bytes > MAX_TOTAL_ASSET_BYTES:
        raise MagicIAError("La selezione supera il limite complessivo di 400 MB.")
    if cancel_event is not None and cancel_event.is_set():
        raise MagicIAError("Elaborazione annullata.")

    api_key = os.environ["MAGICIA_API_KEY"].strip()
    model = os.environ["MAGICIA_MODEL"].strip()
    base_url = os.environ["MAGICIA_API_BASE_URL"].strip().rstrip("/")
    if not base_url.startswith("https://"):
        raise MagicIAError("L'indirizzo del provider IA deve usare HTTPS.")

    media_parts = _media_parts(asset_paths, cancel_event)
    preferences = _normalise_options(options)
    prompt = (
        "Sei MagicIAedit, un assistente di montaggio video. Analizza solo i media "
        "forniti e crea una proposta breve, coerente e modificabile. Per ogni clip "
        "usa esclusivamente uno degli assetId forniti. Per i video indica sourceStartMs. "
        "Restituisci SOLO JSON con title, description e clips; ogni clip deve avere "
        "assetId, sourceStartMs, durationMs, transitionAfterMs, transitionAfter e reason. "
        "Non inventare contenuti o asset. Confronta i fotogrammi nel tempo, evita ripetizioni e scegli intervalli con soggetto leggibile, dettaglio e luminosità adeguati. I segnali brightness, contrast e detail sono indizi tecnici, non verità semantiche: valuta anche il contenuto visivo. Per i video sourceStartMs deve corrispondere a un momento realmente campionato o vicino ad esso. Alterna inquadrature, conserva la continuità narrativa e motiva brevemente ogni scelta in reason. "
        f"Preferenze creative validate: {json.dumps(preferences, ensure_ascii=False)}. "
        "Rispetta stile, ritmo, formato, lingua dei testi e durata obiettivo; "
        "la durata finale può essere più breve se i media non offrono materiale sufficiente."
    )
    payload = {
        "model": model,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": "Rispondi esclusivamente con JSON valido."},
            {"role": "user", "content": [{"type": "text", "text": prompt}, *media_parts]},
        ],
    }
    request = urllib.request.Request(
        base_url + "/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        opener = urllib.request.build_opener(_NoRedirect)
        with opener.open(request, timeout=150) as response:
            result = json.loads(response.read(8 * 1024 * 1024).decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # Do not return provider response bodies; they can contain sensitive details.
        raise MagicIAError(f"Il provider IA ha risposto con HTTP {exc.code}.") from exc
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise MagicIAError("Il servizio IA non è raggiungibile o ha restituito una risposta non valida.") from exc

    try:
        text = result["choices"][0]["message"]["content"]
        if not isinstance(text, str):
            raise TypeError("content")
        plan = _normalise_plan(json.loads(text), set(asset_paths))
    except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise MagicIAError("Il provider IA non ha restituito un piano MagicIAedit valido.") from exc
    if cancel_event is not None and cancel_event.is_set():
        raise MagicIAError("Elaborazione annullata.")
    return plan
