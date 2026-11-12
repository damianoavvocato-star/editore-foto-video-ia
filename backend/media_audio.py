"""Safe FFmpeg audio extraction for speech recognition jobs.

The caller owns authorization and media lifecycle. This module never shells out
through a command interpreter and never contacts a remote service.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

MAX_MEDIA_BYTES = 2 * 1024 * 1024 * 1024
MAX_AUDIO_BYTES = 512 * 1024 * 1024
DEFAULT_TIMEOUT_SECONDS = 180


class AudioExtractionError(ValueError):
    """Raised when an audio track cannot be extracted safely."""


def extract_audio_track(
    source_path: str | Path,
    output_path: str | Path,
    *,
    ffmpeg_bin: str = "ffmpeg",
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
) -> Path:
    """Extract the first audio stream to mono 16 kHz PCM WAV.

    The destination must not already exist. A successful process is not trusted
    until the resulting file is checked for existence, size and WAV signature.
    """
    if not isinstance(ffmpeg_bin, str) or not ffmpeg_bin.strip():
        raise AudioExtractionError("Configurazione FFmpeg non valida.")
    if isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, int):
        raise AudioExtractionError("Timeout non valido.")
    if not 1 <= timeout_seconds <= 900:
        raise AudioExtractionError("Timeout fuori dai limiti consentiti.")

    source = Path(source_path)
    destination = Path(output_path)
    try:
        if source.is_symlink() or destination.is_symlink():
            raise AudioExtractionError("I collegamenti simbolici non sono consentiti.")
        source = source.resolve(strict=True)
        destination = destination.resolve(strict=False)
    except OSError as exc:
        raise AudioExtractionError("Percorso del file multimediale non valido.") from exc

    if not source.is_file():
        raise AudioExtractionError("Il file sorgente non è un file regolare.")
    try:
        source_size = source.stat().st_size
    except OSError as exc:
        raise AudioExtractionError("Impossibile leggere il file sorgente.") from exc
    if source_size <= 0 or source_size > MAX_MEDIA_BYTES:
        raise AudioExtractionError("Dimensione del file sorgente fuori dai limiti.")
    if source == destination or destination.exists():
        raise AudioExtractionError("Il file di destinazione esiste già o non è valido.")
    if not destination.parent.is_dir():
        raise AudioExtractionError("La cartella di destinazione non esiste.")

    command = [
        ffmpeg_bin, "-nostdin", "-hide_banner", "-loglevel", "error",
        "-i", os.fspath(source), "-map", "0:a:0", "-vn", "-ac", "1",
        "-ar", "16000", "-c:a", "pcm_s16le", "-f", "wav", "-n",
        os.fspath(destination),
    ]
    try:
        completed = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout_seconds,
        )
    except FileNotFoundError as exc:
        raise AudioExtractionError("FFmpeg non è installato sul server.") from exc
    except subprocess.TimeoutExpired as exc:
        destination.unlink(missing_ok=True)
        raise AudioExtractionError("Estrazione audio scaduta per timeout.") from exc
    except OSError as exc:
        destination.unlink(missing_ok=True)
        raise AudioExtractionError("Avvio di FFmpeg non riuscito.") from exc

    if completed.returncode != 0:
        destination.unlink(missing_ok=True)
        raise AudioExtractionError("FFmpeg non è riuscito a estrarre una traccia audio.")
    try:
        if not destination.is_file() or destination.is_symlink():
            raise AudioExtractionError("FFmpeg non ha prodotto un file audio valido.")
        size = destination.stat().st_size
        with destination.open("rb") as audio_file:
            signature = audio_file.read(12)
        if size < 44 or size > MAX_AUDIO_BYTES or signature[:4] != b"RIFF" or signature[8:12] != b"WAVE":
            destination.unlink(missing_ok=True)
            raise AudioExtractionError("Il file audio estratto non è un WAV valido.")
    except OSError as exc:
        destination.unlink(missing_ok=True)
        raise AudioExtractionError("Impossibile verificare il file audio estratto.") from exc
    return destination
