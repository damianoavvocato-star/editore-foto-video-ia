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
