from backend.security_notifications import send_security_alert


def test_security_alert_delivery_is_disabled_without_explicit_configuration(monkeypatch):
    monkeypatch.delenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL", raising=False)
    monkeypatch.delenv("MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN", raising=False)
    assert send_security_alert("auth.new_session", "user-id", "owner") is False


def test_security_alert_webhook_requires_https_and_both_secrets(monkeypatch):
    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL", "http://alerts.example.test/hook")
    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN", "test-secret")
    assert send_security_alert("auth.new_ip", "user-id", "owner") is False

    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL", "https://alerts.example.test/hook")
    monkeypatch.delenv("MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN")
    assert send_security_alert("auth.new_ip", "user-id", "owner") is False


def test_security_alert_rejects_unknown_event_types(monkeypatch):
    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL", "https://alerts.example.test/hook")
    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN", "test-secret")
    assert send_security_alert("arbitrary.event", "user-id", "owner") is False


def test_security_alert_sends_minimal_payload_without_credentials(monkeypatch):
    import json
    import backend.security_notifications as notifications

    captured = {}

    class FakeResponse:
        status = 202

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    class FakeOpener:
        def open(self, request, timeout):
            captured["url"] = request.full_url
            captured["authorization"] = request.get_header("Authorization")
            captured["timeout"] = timeout
            captured["payload"] = json.loads(request.data.decode("utf-8"))
            return FakeResponse()

    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL", "https://alerts.example.test/hook")
    monkeypatch.setenv("MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN", "secret-webhook-token")
    monkeypatch.setattr(notifications, "build_opener", lambda *_args: FakeOpener())

    assert notifications.send_security_alert(
        "auth.new_ip", "opaque-user-id", "owner", "unseen_client_network"
    ) is True
    assert captured["authorization"] == "Bearer secret-webhook-token"
    assert captured["timeout"] == 3
    assert captured["payload"]["userId"] == "opaque-user-id"
    assert captured["payload"]["reason"] == "unseen_client_network"
    assert "secret-webhook-token" not in json.dumps(captured["payload"])
    assert "ipAddress" not in captured["payload"]
    assert "password" not in captured["payload"]
