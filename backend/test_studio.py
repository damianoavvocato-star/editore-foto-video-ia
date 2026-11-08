"""Tests for Synthesia Studio request validation and private draft storage."""
import pytest
from pydantic import ValidationError

from backend.studio import StudioJobRequest, StudioJobStore, StudioRequestError


def test_studio_accepts_twenty_distinct_languages():
    languages = [f"l{index:02d}" for index in range(20)]
    request = StudioJobRequest(task="script_to_video", script="Hello", targetLanguages=languages)
    request.validate_policy()
    assert len(request.targetLanguages) == 20


def test_studio_rejects_duplicate_or_invalid_languages():
    with pytest.raises(ValidationError):
        StudioJobRequest(task="script_to_video", script="Hello", targetLanguages=["it-IT", "it-IT"])
    with pytest.raises(ValidationError):
        StudioJobRequest(task="script_to_video", script="Hello", targetLanguages=["italiano"])


def test_source_language_cannot_be_a_destination():
    request = StudioJobRequest(
        task="script_to_video", script="Hello",
        sourceLanguage="en-US", targetLanguages=["en-US"],
    )
    with pytest.raises(StudioRequestError):
        request.validate_policy()


def test_personal_avatar_requires_explicit_consent():
    request = StudioJobRequest(
        task="avatar_video", script="Welcome",
        avatarMode="personal", avatarConsent=False,
    )
    with pytest.raises(StudioRequestError, match="consenso"):
        request.validate_policy()


def test_voice_clone_requires_explicit_consent():
    request = StudioJobRequest(
        task="script_to_video", script="Welcome",
        voiceMode="clone", voiceConsent=False,
    )
    with pytest.raises(StudioRequestError, match="consenso"):
        request.validate_policy()


def test_document_and_slide_jobs_require_source_files():
    for task in ("document_to_video", "slides_to_video", "translate_dub"):
        request = StudioJobRequest(task=task)
        with pytest.raises(StudioRequestError):
            request.validate_policy()


def test_interactive_video_must_be_explicitly_enabled():
    request = StudioJobRequest(task="interactive_video", script="Question")
    with pytest.raises(StudioRequestError):
        request.validate_policy()


def test_idempotent_draft_replay_and_user_isolation(tmp_path):
    store = StudioJobStore(tmp_path / "studio.sqlite3")
    request = StudioJobRequest(task="script_to_video", script="A short intro")
    first, created = store.create_draft("user-a", request, "request-1")
    replay, replay_created = store.create_draft("user-a", request, "request-1")
    assert created is True
    assert replay_created is False
    assert replay["jobId"] == first["jobId"]
    assert store.get("user-b", first["jobId"]) is None
    assert store.get("user-a", first["jobId"])["state"] == "draft"


def test_idempotency_key_cannot_be_reused_for_different_content(tmp_path):
    store = StudioJobStore(tmp_path / "studio.sqlite3")
    store.create_draft(
        "user-a", StudioJobRequest(task="script_to_video", script="First"), "same-key"
    )
    with pytest.raises(StudioRequestError, match="idempotenza"):
        store.create_draft(
            "user-a", StudioJobRequest(task="script_to_video", script="Second"), "same-key"
        )


def test_only_owner_can_delete_draft(tmp_path):
    store = StudioJobStore(tmp_path / "studio.sqlite3")
    draft, _ = store.create_draft("user-a", StudioJobRequest(task="script_to_video", script="Hello"))
    assert store.delete_draft("user-b", draft["jobId"]) is False
    assert store.delete_draft("user-a", draft["jobId"]) is True


def test_persisted_drafts_survive_store_recreation(tmp_path):
    path = tmp_path / "studio.sqlite3"
    store = StudioJobStore(path)
    draft, _ = store.create_draft("user-a", StudioJobRequest(task="script_to_video", script="Hello"))
    reopened = StudioJobStore(path)
    assert reopened.get("user-a", draft["jobId"])["request"]["script"] == "Hello"
