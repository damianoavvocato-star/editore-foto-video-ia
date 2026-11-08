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


def matching_counter(
    secret: str, supplied: str, timestamp: int | float | None = None,
    window: int = 1, digits: int = 6, period: int = 30,
) -> int | None:
    """Return the matched moving counter so callers can atomically prevent replay.

    Every permitted counter is checked. If an extremely unlikely numeric collision
    occurs in the accepted window, the greatest matching counter is returned.
    """
    if (not isinstance(supplied, str) or not supplied.isdigit()
            or len(supplied) != digits or digits not in (6, 8)):
        return None
    if not isinstance(window, int) or isinstance(window, bool) or not 0 <= window <= 2:
        return None
    if not isinstance(period, int) or isinstance(period, bool) or not 15 <= period <= 120:
        return None
    now = time.time() if timestamp is None else timestamp
    try:
        center = int(now // period)
        matched = None
        for offset in range(-window, window + 1):
            counter = center + offset
            if counter < 0:
                candidate = "!" * digits
            else:
                candidate = code_at(secret, counter * period, digits, period)
            equal = hmac.compare_digest(candidate, supplied)
            if equal:
                matched = counter if matched is None else max(matched, counter)
        return matched
    except (TypeError, ValueError, OverflowError, struct.error):
        return None


def verify_code(
    secret: str, supplied: str, timestamp: int | float | None = None,
    window: int = 1, digits: int = 6, period: int = 30,
) -> bool:
    return matching_counter(secret, supplied, timestamp, window, digits, period) is not None
