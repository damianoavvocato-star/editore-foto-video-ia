"""Tests for account-scoped MagicIAedit speech job orchestration."""
import subprocess

import pytest

from backend.speech_job import SpeechJobError, process_speech_job


ASSET_ID = "a" * 32


def write_wav(path):
    path.write_bytes(b"RIFF" + (36).to_bytes(4, "little") + b"WAVE" + b"\x00" * 32)


class Provider:
    def transcribe(self, asset_path, language=None):
        assert asset_path.endswith("source.wav")
        assert language == "it"
        return {"segments": [
            {"segmentId": "s1", "startMs": 0, "endMs": 1000, "text": "Ciao"}
        ]}

    def translate(self, segments, target_language):
        return {"segments": [
            {"segmentId": segments[0]["segmentId"], "text": f"Hello {target_language}"}
        ]}


def test_speech_job_transcribes_and_builds_multiple_language_subtitles(tmp_path, monkeypatch):
    assets, work = tmp_path / "assets", tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    (assets / f"{ASSET_ID}.mp4").write_bytes(b"media")
    seen = {}

    def fake_extract(source, output, **kwargs):
        seen["source"] = source
        write_wav(output)
        return output

    monkeypatch.setattr("backend.speech_job.extract_audio_track", fake_extract)
    result = process_speech_job(
        user_id="user-1", asset_id=ASSET_ID, duration_ms=2000,
        asset_root=assets, work_root=work,
        authorize_asset=lambda user, asset: user == "user-1" and asset == ASSET_ID,
        provider=Provider(), source_language="it", target_languages=["en", "fr"],
    )
    assert set(result["languages"]) == {"it", "en", "fr"}
    assert "Ciao" in result["languages"]["it"]["srt"]
    assert "Hello en" in result["languages"]["en"]["vtt"]
    assert "Hello fr" in result["languages"]["fr"]["srt"]
    assert result["temporaryAudioRemoved"] is True
    assert list(work.iterdir()) == []


def test_speech_job_rejects_unowned_asset_before_extraction(tmp_path, monkeypatch):
    assets, work = tmp_path / "assets", tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    (assets / f"{ASSET_ID}.mp4").write_bytes(b"media")
    monkeypatch.setattr(
        "backend.speech_job.extract_audio_track",
        lambda *args, **kwargs: pytest.fail("must not extract unauthorized media"),
    )
    with pytest.raises(SpeechJobError, match="non autorizzato"):
        process_speech_job(
            user_id="other-user", asset_id=ASSET_ID, duration_ms=1000,
            asset_root=assets, work_root=work,
            authorize_asset=lambda _user, _asset: False, provider=Provider(),
        )


@pytest.mark.parametrize("asset_id", ["../escape", "A" * 32, "short"])
def test_speech_job_rejects_invalid_asset_ids(tmp_path, asset_id):
    assets, work = tmp_path / "assets", tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    with pytest.raises(SpeechJobError, match="Identificativo"):
        process_speech_job(
            user_id="user-1", asset_id=asset_id, duration_ms=1000,
            asset_root=assets, work_root=work,
            authorize_asset=lambda *_: True, provider=Provider(),
        )


def test_speech_job_rejects_duplicate_or_source_target_language(tmp_path):
    assets, work = tmp_path / "assets", tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    (assets / f"{ASSET_ID}.mp4").write_bytes(b"media")
    for targets in (["en", "en"], ["it"]):
        with pytest.raises(SpeechJobError):
            process_speech_job(
                user_id="user-1", asset_id=ASSET_ID, duration_ms=1000,
                asset_root=assets, work_root=work,
                authorize_asset=lambda *_: True, provider=Provider(),
                source_language="it", target_languages=targets,
            )


def test_speech_job_rejects_ambiguous_asset_matches(tmp_path):
    assets, work = tmp_path / "assets", tmp_path / "work"
    assets.mkdir()
    work.mkdir()
    (assets / f"{ASSET_ID}.mp4").write_bytes(b"media")
    (assets / f"{ASSET_ID}.mov").write_bytes(b"media")
    with pytest.raises(SpeechJobError, match="ambiguo"):
        process_speech_job(
            user_id="user-1", asset_id=ASSET_ID, duration_ms=1000,
            asset_root=assets, work_root=work,
            authorize_asset=lambda *_: True, provider=Provider(),
        )
