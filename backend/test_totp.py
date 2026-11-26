from backend.totp import code_at, generate_secret, matching_counter, verify_code


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


def test_totp_verification_checks_the_entire_window(monkeypatch):
    import backend.totp as totp

    checked = []

    def fake_code_at(secret, timestamp, digits=6, period=30):
        checked.append(timestamp)
        return "123456" if timestamp == 90 else "000000"

    monkeypatch.setattr(totp, "code_at", fake_code_at)
    assert totp.verify_code("unused", "123456", timestamp=90, window=1)
    assert checked == [60, 90, 120]


def test_totp_verification_rejects_invalid_window_and_code_shape():
    secret = generate_secret()
    assert verify_code(secret, "123456", timestamp=90, window=3) is False
    assert verify_code(secret, "12345x", timestamp=90) is False


def test_matching_counter_returns_counter_for_replay_tracking():
    secret = generate_secret()
    assert matching_counter(secret, code_at(secret, 90), timestamp=90) == 3
    assert matching_counter(secret, code_at(secret, 90), timestamp=120) == 3
    assert matching_counter(secret, "12345x", timestamp=90) is None
    assert matching_counter(secret, code_at(secret, 90), timestamp=90, window=3) is None


def test_matching_counter_checks_all_steps_even_after_match(monkeypatch):
    import backend.totp as totp

    checked = []

    def fake_code_at(secret, timestamp, digits=6, period=30):
        checked.append(timestamp)
        return "123456" if timestamp == 90 else "000000"

    monkeypatch.setattr(totp, "code_at", fake_code_at)
    assert totp.matching_counter("unused", "123456", timestamp=90, window=1) == 3
    assert checked == [60, 90, 120]
