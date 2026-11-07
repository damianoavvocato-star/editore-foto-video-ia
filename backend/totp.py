"""RFC 6238 TOTP primitives. Secret storage/encryption and recovery flows are separate."""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import struct
import time


def generate_secret(length: int = 20) -> str:
    if not isinstance(length, int) or not 16 <= length <= 64:
        raise ValueError("Lunghezza segreto TOTP non valida.")
    return base64.b32encode(secrets.token_bytes(length)).decode("ascii").rstrip("=")


def code_at(secret: str, timestamp: int | float, digits: int = 6, period: int = 30) -> str:
    if digits not in (6, 8) or period < 15 or period > 120:
        raise ValueError("Parametri TOTP non validi.")
    normalized = secret.strip().upper()
    padding = "=" * ((8 - len(normalized) % 8) % 8)
    try:
        key = base64.b32decode(normalized + padding, casefold=True)
    except Exception as exc:
        raise ValueError("Segreto TOTP non valido.") from exc
    counter = int(timestamp // period)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    binary = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(binary % (10 ** digits)).zfill(digits)


def verify_code(
    secret: str, supplied: str, timestamp: int | float | None = None,
    window: int = 1, digits: int = 6, period: int = 30,
) -> bool:
    if not isinstance(supplied, str) or not supplied.isdigit() or len(supplied) != digits:
        return False
    if not isinstance(window, int) or not 0 <= window <= 2:
        return False
    now = time.time() if timestamp is None else timestamp
    try:
        candidates = (code_at(secret, now + offset * period, digits, period)
                      for offset in range(-window, window + 1))
        return any(hmac.compare_digest(candidate, supplied) for candidate in candidates)
    except (TypeError, ValueError, OverflowError):
        return False
