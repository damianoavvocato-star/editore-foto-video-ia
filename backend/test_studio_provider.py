"""Contract tests for the Synthesia Video API adapter; no live API calls."""
import json

import httpx
import pytest

from backend.studio import StudioJobRequest
from backend.studio_provider import SynthesiaProviderError, SynthesiaVideoProvider


VIDEO_ID = "00db5057-ad78-49ab-9e1d-00f1cd891273"
TEMPLATE_ID = "3d6b3a1e-2d4f-4b1e-9d6c-4c2a1b8f9e00"


def test_provider_is_not_configured_without_server_credentials():
    provider = SynthesiaVideoProvider()
    assert provider.configured is False
    with pytest.raises(SynthesiaProviderError, match="non configurato"):
        provider.create_video(
            StudioJobRequest(task="script_to_video", script="Ciao")
        )


def test_environment_configuration_defaults_to_free_test_mode():
    provider = SynthesiaVideoProvider.from_environment({
        "SYNTHESIA_API_KEY": "server-secret",
        "SYNTHESIA_DEFAULT_AVATAR_ID": "anna_costume1_cameraA",
    })
    assert provider.configured is True
    assert provider.test_mode is True


def test_environment_configuration_fails_closed_for_paid_mode():
    env = {
        "SYNTHESIA_API_KEY": "server-secret",
        "SYNTHESIA_DEFAULT_AVATAR_ID": "anna_costume1_cameraA",
        "SYNTHESIA_TEST_MODE": "false",
    }
    with pytest.raises(SynthesiaProviderError, match="generazione a pagamento"):
        SynthesiaVideoProvider.from_environment(env)
    env["SYNTHESIA_ALLOW_PAID_GENERATION"] = "true"
    assert SynthesiaVideoProvider.from_environment(env).test_mode is False


def test_environment_configuration_rejects_ambiguous_test_mode():
    with pytest.raises(SynthesiaProviderError, match="true oppure false"):
        SynthesiaVideoProvider.from_environment({"SYNTHESIA_TEST_MODE": "maybe"})


def test_create_video_uses_private_test_request_and_official_v2_contract():
    captured = {}

    def handler(request):
        captured["url"] = str(request.url)
        captured["authorization"] = request.headers["Authorization"]
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            201,
            json={
                "id": VIDEO_ID,
                "status": "in_progress",
                "title": "Demo",
                "visibility": "private",
                "test": True,
            },
        )

    provider = SynthesiaVideoProvider(
        api_key="server-secret",
        avatar_id="anna_costume1_cameraA",
        transport=httpx.MockTransport(handler),
    )
    result = provider.create_video(
        StudioJobRequest(task="script_to_video", title="Demo", script="Ciao mondo"),
        callback_id="draft-123",
    )

    assert provider.configured is True
    assert captured["url"] == "https://api.synthesia.io/v2/videos"
    assert captured["authorization"] == "server-secret"
    assert captured["body"] == {
        "title": "Demo",
        "input": [{
            "scriptText": "Ciao mondo",
            "avatar": "anna_costume1_cameraA",
            "background": "off_white",
        }],
        "visibility": "private",
        "test": True,
        "callbackId": "draft-123",
    }
    assert result["providerVideoId"] == VIDEO_ID
    assert result["providerStatus"] == "in_progress"


def test_template_video_uses_official_from_template_contract():
    captured = {}

    def handler(request):
        captured["url"] = str(request.url)
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            201,
            json={
                "id": VIDEO_ID,
                "status": "in_progress",
                "title": "Welcome Damiano",
                "visibility": "private",
                "test": True,
            },
        )

    provider = SynthesiaVideoProvider(
        api_key="server-secret",
        avatar_id="avatar",
        transport=httpx.MockTransport(handler),
    )
    result = provider.create_video(
        StudioJobRequest(
            task="bulk_personalization",
            title="Welcome",
            templateId=TEMPLATE_ID,
            variables={"first_name": "Damiano", "product": "Studio"},
        ),
        callback_id="batch-item-01",
    )

    assert captured["url"] == "https://api.synthesia.io/v2/videos/fromTemplate"
    assert captured["body"] == {
        "title": "Welcome",
        "templateId": TEMPLATE_ID,
        "templateData": {"first_name": "Damiano", "product": "Studio"},
        "visibility": "private",
        "test": True,
        "callbackId": "batch-item-01",
    }
    assert result["providerVideoId"] == VIDEO_ID


def test_template_video_rejects_invalid_template_and_empty_variables():
    provider = SynthesiaVideoProvider(api_key="key", avatar_id="avatar")
    with pytest.raises(SynthesiaProviderError, match="template ID UUID"):
        provider.create_video(
            StudioJobRequest(
                task="bulk_personalization",
                templateId="not-a-uuid",
                variables={"name": "A"},
            )
        )
    with pytest.raises(SynthesiaProviderError, match="almeno una variabile"):
        provider.create_video(
            StudioJobRequest(task="bulk_personalization", templateId=TEMPLATE_ID)
        )


def test_provider_rejects_unsupported_tasks_before_network():
    provider = SynthesiaVideoProvider(api_key="key", avatar_id="avatar")
    with pytest.raises(SynthesiaProviderError, match="script/avatar e template"):
        provider.create_video(
            StudioJobRequest(
                task="document_to_video",
                sourceAssetIds=["a" * 32],
            )
        )


def test_provider_rejects_empty_script_and_invalid_callback():
    provider = SynthesiaVideoProvider(api_key="key", avatar_id="avatar")
    with pytest.raises(SynthesiaProviderError, match="script"):
        provider.create_video(StudioJobRequest(task="script_to_video"))
    with pytest.raises(SynthesiaProviderError, match="Callback"):
        provider.create_video(
            StudioJobRequest(task="script_to_video", script="Test"),
            callback_id=" ",
        )


def test_retrieve_video_polls_status_and_returns_time_limited_download():
    def handler(request):
        assert request.url.path == f"/v2/videos/{VIDEO_ID}"
        assert request.headers["Authorization"] == "server-secret"
        return httpx.Response(
            200,
            json={
                "id": VIDEO_ID,
                "status": "complete",
                "download": "https://temporary.example/video.mp4",
                "duration": "00:00:12",
                "captions": {"srt": "https://temporary.example/captions.srt"},
            },
        )

    provider = SynthesiaVideoProvider(
        api_key="server-secret",
        avatar_id="avatar",
        transport=httpx.MockTransport(handler),
    )
    result = provider.retrieve_video(VIDEO_ID)
    assert result["providerStatus"] == "complete"
    assert result["downloadUrl"] == "https://temporary.example/video.mp4"
    assert result["duration"] == "00:00:12"


def test_retrieve_video_rejects_non_uuid_ids_before_network():
    provider = SynthesiaVideoProvider(api_key="key", avatar_id="avatar")
    with pytest.raises(SynthesiaProviderError, match="ID video"):
        provider.retrieve_video("../../secrets")


def test_provider_rejects_unknown_status_and_malformed_provider_id():
    provider = SynthesiaVideoProvider(api_key="key", avatar_id="avatar")
    with pytest.raises(SynthesiaProviderError, match="stato video sconosciuto"):
        provider._video_metadata({"id": VIDEO_ID, "status": "queued"}, "Demo")
    with pytest.raises(SynthesiaProviderError, match="ID video non valido"):
        provider._video_metadata({"id": "not-an-id", "status": "in_progress"}, "Demo")


def test_provider_wraps_http_failures_without_leaking_credentials():
    def handler(_request):
        return httpx.Response(403, json={"message": "insufficient_scope"})

    provider = SynthesiaVideoProvider(
        api_key="do-not-leak-this",
        avatar_id="avatar",
        transport=httpx.MockTransport(handler),
    )
    with pytest.raises(SynthesiaProviderError) as error:
        provider.create_video(
            StudioJobRequest(task="script_to_video", script="Test")
        )
    assert "do-not-leak-this" not in str(error.value)
