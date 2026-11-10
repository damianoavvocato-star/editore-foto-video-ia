import pytest
from pydantic import ValidationError

from backend.magiclink import MagicLinkRequest, classify_platform, describe_link


@pytest.mark.parametrize(
    ("url", "platform"),
    [
        ("https://www.tiktok.com/@creator/video/123", "tiktok"),
        ("https://youtu.be/abc123", "youtube"),
        ("https://www.instagram.com/reel/example/", "instagram"),
        ("https://vimeo.com/12345", "vimeo"),
        ("https://example.org/article", "website"),
        ("https://evil-tiktok.com/video", "website"),
    ],
)
def test_magiclink_classifies_supported_platforms_and_generic_sites(url, platform):
    assert classify_platform(url) == platform


@pytest.mark.parametrize(
    "url",
    [
        "file:///etc/passwd",
        "ftp://example.com/video",
        "http://localhost/admin",
        "http://127.0.0.1/private",
        "http://10.0.0.1/internal",
        "http://192.168.1.10/media",
        "http://[::1]/private",
        "http://service.local/video",
        "http://user:password@example.com/video",
        "https://example.com:8443/video",
    ],
)
def test_magiclink_rejects_non_public_or_unsafe_urls(url):
    with pytest.raises(ValidationError):
        MagicLinkRequest(url=url)


def test_magiclink_analysis_is_explicitly_metadata_only():
    request = MagicLinkRequest(
        url="https://www.tiktok.com/@creator/video/123",
        instruction="Traduci tutta la serie in italiano",
    )
    result = describe_link(request)
    assert result["platform"] == "tiktok"
    assert result["contentAccess"] == "not_fetched"
    assert result["providerState"] == "not_configured"
    assert result["instruction"] == "Traduci tutta la serie in italiano"
    assert "translate_subtitles" in result["availableNextSteps"]


def test_magiclink_rejects_overlong_instruction():
    with pytest.raises(ValidationError):
        MagicLinkRequest(url="https://example.org/video", instruction="x" * 1001)
