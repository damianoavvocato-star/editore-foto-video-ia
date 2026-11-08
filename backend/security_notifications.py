"""Optional HTTPS webhook delivery for security events.

No notification credentials or destination are stored in source control. Events
contain opaque account IDs and coarse event metadata only, never passwords,
tokens, IP addresses, TOTP seeds, or recovery codes.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


_ALLOWED_EVENTS = {
    "auth.new_session",
    "auth.new_ip",
    "auth.login_rate_limited",
}


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def send_security_alert(
    event: str, user_id: str | None, role: str | None, reason: str | None = None
) -> bool:
    """Send one minimal alert to a configured HTTPS webhook; fail closed/no-op otherwise."""
    if event not in _ALLOWED_EVENTS:
        return False
    endpoint = os.getenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL", "").strip()
    secret = os.getenv("MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN", "").strip()
    parsed = urlsplit(endpoint)
    if (not endpoint or not secret or parsed.scheme.lower() != "https"
            or not parsed.hostname or parsed.username or parsed.password):
        return False

    payload = {
        "event": event,
        "userId": user_id,
        "role": role,
        "reason": reason,
        "occurredAt": int(time.time()),
    }
    request = Request(
        endpoint,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {secret}",
        },
        method="POST",
    )
    try:
        with build_opener(_NoRedirect).open(request, timeout=3) as response:
            return 200 <= response.status < 300
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as exc:
        logging.warning("Security webhook delivery failed (%s)", type(exc).__name__)
        return False


def dispatch_security_alert(
    event: str, user_id: str | None, role: str | None, reason: str | None = None
) -> None:
    """Deliver asynchronously so a notification provider cannot delay authentication."""
    if not os.getenv("MEDIA_SECURITY_ALERT_WEBHOOK_URL") or not os.getenv(
        "MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN"
    ):
        return
    threading.Thread(
        target=send_security_alert,
        args=(event, user_id, role, reason),
        daemon=True,
        name="security-alert-delivery",
    ).start()
