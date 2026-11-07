from backend.totp import code_at, generate_secret, verify_code


def test_totp_matches_rfc6238_sha1_six_digit_vector():
    # RFC 6238 test secret, timestamp 59, 30-second period.
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    assert code_at(secret, 59, digits=8) == "94287082"


def test_totp_verification_accepts_current_and_adjacent_window():
    secret = generate_secret()
    code = code_at(secret, 90)
    assert verify_code(secret, code, timestamp=90)
    assert verify_code(secret, code, timestamp=120, window=1)
    assert not verify_code(secret, "bad", timestamp=90)
    assert not verify_code(secret, "123", timestamp=90)


def test_totp_rejects_invalid_secrets_and_parameters():
    assert verify_code("not valid!", "123456", timestamp=90) is False
