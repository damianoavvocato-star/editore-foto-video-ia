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



def test_magiclink_api_requires_authenticated_account():
    from fastapi.testclient import TestClient
    from backend import server

    client = TestClient(server.app)
    assert client.get("/v1/magiclink/capabilities").status_code == 401
    assert client.post(
        "/v1/magiclink/analyze", json={"url": "https://example.org/video"}
    ).status_code == 401


def test_magiclink_api_recognizes_link_without_fetching_remote_content(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from backend import server
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    user = store.register("magiclink_user", "a sufficiently long password")
    token, _ = store.issue_session(user["userId"])
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)
    headers = {"Authorization": f"Bearer {token}"}

    capabilities = client.get("/v1/magiclink/capabilities", headers=headers)
    assert capabilities.status_code == 200
    assert capabilities.json()["urlRecognition"] is True
    assert capabilities.json()["remoteContentExtraction"] is False

    response = client.post(
        "/v1/magiclink/analyze",
        headers=headers,
        json={
            "url": "https://www.tiktok.com/@creator/video/123",
            "instruction": "Traduci tutte le puntate in italiano",
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["platform"] == "tiktok"
    assert payload["contentAccess"] == "not_fetched"
    assert payload["providerState"] == "not_configured"
    assert payload["instruction"] == "Traduci tutte le puntate in italiano"


def test_magiclink_api_rejects_private_network_targets_for_authenticated_user(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from backend import server
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    user = store.register("magiclink_private", "a sufficiently long password")
    token, _ = store.issue_session(user["userId"])
    monkeypatch.setattr(server, "_account_store", lambda: store)
    response = TestClient(server.app).post(
        "/v1/magiclink/analyze",
        headers={"Authorization": f"Bearer {token}"},
        json={"url": "http://127.0.0.1/admin"},
    )
    assert response.status_code == 422
