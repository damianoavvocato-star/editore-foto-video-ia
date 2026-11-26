"""Unit tests for safe FFmpeg audio extraction."""
import subprocess

import pytest

from backend.media_audio import AudioExtractionError, extract_audio_track


def wav(path):
    path.write_bytes(b"RIFF" + (36).to_bytes(4, "little") + b"WAVE" + b"\x00" * 32)


def test_extract_audio_uses_argument_list_and_validates_wav(tmp_path, monkeypatch):
    source = tmp_path / "input.mp4"
    source.write_bytes(b"video")
    output = tmp_path / "audio.wav"
    captured = {}

    def fake_run(command, **kwargs):
        captured["command"] = command
        captured["kwargs"] = kwargs
        wav(output)
        return subprocess.CompletedProcess(command, 0, b"", b"")

    monkeypatch.setattr("backend.media_audio.subprocess.run", fake_run)
    result = extract_audio_track(source, output)
    assert result == output.resolve()
    assert captured["command"][0] == "ffmpeg"
    assert "-map" in captured["command"] and "0:a:0" in captured["command"]
    assert "-ar" in captured["command"] and "16000" in captured["command"]
    assert captured["kwargs"]["timeout"] == 180
    assert captured["kwargs"]["stdin"] == subprocess.DEVNULL


def test_extract_audio_fails_when_ffmpeg_is_missing(tmp_path, monkeypatch):
    source = tmp_path / "input.mp4"
    source.write_bytes(b"video")
    output = tmp_path / "audio.wav"

    def missing(*args, **kwargs):
        raise FileNotFoundError()

    monkeypatch.setattr("backend.media_audio.subprocess.run", missing)
    with pytest.raises(AudioExtractionError, match="non è installato"):
        extract_audio_track(source, output)
    assert not output.exists()


def test_extract_audio_cleans_partial_file_after_failure(tmp_path, monkeypatch):
    source = tmp_path / "input.mp4"
    source.write_bytes(b"video")
    output = tmp_path / "audio.wav"

    def fail(command, **kwargs):
        output.write_bytes(b"partial")
        return subprocess.CompletedProcess(command, 1, b"", b"no audio")

    monkeypatch.setattr("backend.media_audio.subprocess.run", fail)
    with pytest.raises(AudioExtractionError):
        extract_audio_track(source, output)
    assert not output.exists()


def test_extract_audio_rejects_invalid_source_destination_and_limits(tmp_path):
    missing = tmp_path / "missing.mp4"
    output = tmp_path / "audio.wav"
    with pytest.raises(AudioExtractionError):
        extract_audio_track(missing, output)
    source = tmp_path / "input.mp4"
    source.write_bytes(b"video")
    with pytest.raises(AudioExtractionError):
        extract_audio_track(source, source)
    with pytest.raises(AudioExtractionError):
        extract_audio_track(source, output, timeout_seconds=0)
    output.write_bytes(b"already exists")
    with pytest.raises(AudioExtractionError):
        extract_audio_track(source, output)


def test_extract_audio_rejects_invalid_output_signature_and_cleans_it(tmp_path, monkeypatch):
    source = tmp_path / "input.mp4"
    source.write_bytes(b"video")
    output = tmp_path / "audio.wav"

    def fake_run(command, **kwargs):
        output.write_bytes(b"not wav")
        return subprocess.CompletedProcess(command, 0, b"", b"")

    monkeypatch.setattr("backend.media_audio.subprocess.run", fake_run)
    with pytest.raises(AudioExtractionError, match="WAV valido"):
        extract_audio_track(source, output)
    assert not output.exists()


def test_extract_audio_converts_timeout_and_removes_partial_output(tmp_path, monkeypatch):
    source = tmp_path / "input.mp4"
    source.write_bytes(b"video")
    output = tmp_path / "audio.wav"

    def timeout(command, **kwargs):
        output.write_bytes(b"partial")
        raise subprocess.TimeoutExpired(command, 1)

    monkeypatch.setattr("backend.media_audio.subprocess.run", timeout)
    with pytest.raises(AudioExtractionError, match="timeout"):
        extract_audio_track(source, output, timeout_seconds=1)
    assert not output.exists()
