"""Tests for individual account authentication primitives."""
import pytest

from backend.accounts import AccountError, AccountStore


def test_passwords_are_not_stored_in_plaintext_and_login_works(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register("editor_user", "correct horse battery staple")
    with store._connect() as db:
        row = db.execute("SELECT password_salt,password_hash FROM accounts WHERE user_id=?",
                         (account["userId"],)).fetchone()
    assert row["password_hash"] != b"correct horse battery staple"
    assert len(row["password_salt"]) == 16
    assert len(row["password_hash"]) == 32

    user, token, expires = store.login("EDITOR_USER", "correct horse battery staple")
    assert user["userId"] == account["userId"]
    assert user["role"] == "user"
    assert expires > 0
    assert store.resolve_session(token)["userId"] == account["userId"]


def test_wrong_password_and_unknown_user_are_rejected(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    store.register("editor_user", "correct horse battery staple")
    with pytest.raises(AccountError, match="Credenziali non valide"):
        store.login("editor_user", "incorrect password")
    with pytest.raises(AccountError, match="Credenziali non valide"):
        store.login("missing_user", "incorrect password")


def test_registration_validates_username_password_and_duplicates(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    with pytest.raises(AccountError):
        store.register("x", "correct horse battery staple")
    with pytest.raises(AccountError):
        store.register("editor_user", "short")
    store.register("editor_user", "correct horse battery staple")
    with pytest.raises(AccountError, match="già utilizzato"):
        store.register("EDITOR_USER", "another correct horse battery")


def test_session_can_be_revoked_and_disabled_account_cannot_login(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register("editor_user", "correct horse battery staple")
    _, token, _ = store.login("editor_user", "correct horse battery staple")
    assert store.revoke_session(token) is True
    assert store.resolve_session(token) is None
    with store._connect() as db:
        db.execute("UPDATE accounts SET disabled_at=1 WHERE user_id=?", (account["userId"],))
    with pytest.raises(AccountError):
        store.login("editor_user", "correct horse battery staple")


def test_owner_bootstrap_is_first_owner_only_and_never_promotes_existing_user(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    user = store.register("regular_user", "correct horse battery staple")
    with pytest.raises(AccountError, match="già utilizzato"):
        store.bootstrap_owner("regular_user", "another correct horse battery")
    owner = store.bootstrap_owner("app_owner", "owner password with enough length")
    assert owner["role"] == "owner"
    assert store.bootstrap_owner("second_owner", "another owner password") is None
    assert store.resolve_session("not-a-real-token") is None
    assert user["role"] == "user"


def test_media_resources_are_bound_to_one_account_and_cannot_be_reassigned(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    first = store.register("first_user", "first account password")
    second = store.register("second_user", "second account password")
    asset_id = "a" * 32

    store.claim_media_resource("asset", asset_id, first["userId"])
    assert store.owns_media_resource("asset", asset_id, first["userId"])
    assert not store.owns_media_resource("asset", asset_id, second["userId"])
    assert store.get_media_resource_owner("asset", asset_id) == first["userId"]

    with pytest.raises(AccountError, match="già associata"):
        store.claim_media_resource("asset", asset_id, second["userId"])


def test_media_ownership_rejects_invalid_resource_and_disabled_owner(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register("media_user", "media account password")
    with pytest.raises(AccountError, match="Identificativo"):
        store.claim_media_resource("asset", "../private", account["userId"])
    with store._connect() as db:
        db.execute("UPDATE accounts SET disabled_at=1 WHERE user_id=?", (account["userId"],))
    with pytest.raises(AccountError, match="Account non disponibile"):
        store.claim_media_resource("job", "b" * 32, account["userId"])

 
def test_audit_events_are_persisted_and_returned_newest_first(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    actor = store.register("audit_owner", "owner account password")
    target = store.register("audit_user", "user account password")
    first = store.record_audit_event(
        actor["userId"], "account.created", target["userId"],
        {"role": "user", "source": "owner_panel"},
    )
    second = store.record_audit_event(
        actor["userId"], "account.disabled", target["userId"],
        {"reason": "owner_action"},
    )
    events = store.list_audit_events(10)
    assert [event["eventId"] for event in events[:2]] == [second, first]
    assert events[0]["action"] == "account.disabled"
    assert events[1]["details"]["role"] == "user"


def test_audit_events_reject_secret_fields_and_unbounded_details(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    actor = store.register("audit_owner", "owner account password")
    with pytest.raises(AccountError, match="credenziali"):
        store.record_audit_event(
            actor["userId"], "account.password_reset",
            details={"temporary_password": "must-not-be-stored"},
        )
    with pytest.raises(AccountError, match="troppo grandi"):
        store.record_audit_event(
            actor["userId"], "account.updated",
            details={"comment": "x" * 5000},
        )


def test_self_registered_account_does_not_require_temporary_password_rotation(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register("self_signup", "self signup password long enough")
    assert account["mustChangePassword"] is False
    user, token, _ = store.login("self_signup", "self signup password long enough")
    assert user["mustChangePassword"] is False
    assert store.resolve_session(token)["mustChangePassword"] is False


def test_bootstrapped_owner_is_not_forced_to_rotate_password(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("initial_owner", "initial owner password long")
    assert owner["mustChangePassword"] is False
    logged_in, token, _ = store.login("initial_owner", "initial owner password long")
    assert logged_in["role"] == "owner"
    assert logged_in["mustChangePassword"] is False
    assert store.resolve_session(token)["mustChangePassword"] is False


def test_totp_replay_counter_is_monotonic_and_rejects_replays(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register("totp_user", "totp account password long")
    user_id = account["userId"]

    assert store.consume_totp_counter(user_id, 100) is True
    assert store.consume_totp_counter(user_id, 100) is False
    assert store.consume_totp_counter(user_id, 99) is False
    assert store.consume_totp_counter(user_id, 101) is True
    assert store.consume_totp_counter(user_id, 102) is True


def test_totp_replay_counter_rejects_invalid_or_disabled_accounts(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    account = store.register("totp_user", "totp account password long")
    user_id = account["userId"]

    assert store.consume_totp_counter(user_id, -1) is False
    assert store.consume_totp_counter(user_id, True) is False
    assert store.consume_totp_counter("", 1) is False
    with store._connect() as db:
        db.execute("UPDATE accounts SET disabled_at=1 WHERE user_id=?", (user_id,))
    assert store.consume_totp_counter(user_id, 1) is False


def test_owner_totp_requires_second_factor_and_recovery_codes_are_one_time(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from backend.totp import code_at
    import time
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)

    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("secure_owner", "owner password long enough")
    _, pre_2fa_token, _ = store.login("secure_owner", "owner password long enough")
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    recovery_codes = store.confirm_totp_setup(
        owner["userId"], code_at(secret, int(time.time()))
    )
    assert len(recovery_codes) == 10
    assert store.totp_enabled(owner["userId"])
    assert store.resolve_session(pre_2fa_token) is None

    with pytest.raises(AccountError, match="Secondo fattore"):
        store.login("secure_owner", "owner password long enough")

    # The setup counter is consumed; use the next moving factor for login.
    next_code = code_at(secret, int(time.time()) + 30)
    user, token, _ = store.login(
        "secure_owner", "owner password long enough", next_code
    )
    assert user["role"] == "owner"
    assert store.resolve_session(token)["userId"] == owner["userId"]

    # A recovery code can replace a TOTP once, and is never reusable.
    _, recovery_token, _ = store.login(
        "secure_owner", "owner password long enough", recovery_codes[0]
    )
    assert store.resolve_session(recovery_token)["userId"] == owner["userId"]
    with pytest.raises(AccountError, match="Secondo fattore"):
        store.login("secure_owner", "owner password long enough", recovery_codes[0])


def test_owner_totp_secret_is_encrypted_and_missing_key_fails_closed(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from backend.accounts import SecurityConfigurationError
    from backend.totp import code_at
    import time
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)

    key = Fernet.generate_key().decode("ascii")
    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", key)
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("secure_owner", "owner password long enough")
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    with store._connect() as db:
        row = db.execute(
            "SELECT totp_pending_secret_enc FROM accounts WHERE user_id=?",
            (owner["userId"],),
        ).fetchone()
    assert secret.encode("ascii") not in bytes(row["totp_pending_secret_enc"])
    store.confirm_totp_setup(owner["userId"], code_at(secret, int(time.time())))

    monkeypatch.delenv("MEDIA_TOTP_ENCRYPTION_KEY")
    with pytest.raises(SecurityConfigurationError):
        store.login(
            "secure_owner", "owner password long enough",
            code_at(secret, int(time.time()) + 30),
        )


def test_disabling_owner_totp_requires_password_and_second_factor_and_revokes_sessions(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from backend.totp import code_at
    import time
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)

    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("secure_owner", "owner password long enough")
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    store.confirm_totp_setup(owner["userId"], code_at(secret, int(time.time())))
    _, token, _ = store.login(
        "secure_owner", "owner password long enough",
        code_at(secret, int(time.time()) + 30),
    )
    clock += 30

    with pytest.raises(AccountError, match="Password"):
        store.disable_totp(owner["userId"], "wrong password", code_at(secret, int(time.time()) + 30))
    store.disable_totp(
        owner["userId"], "owner password long enough",
        code_at(secret, int(time.time()) + 30),
    )
    assert store.totp_enabled(owner["userId"]) is False
    assert store.resolve_session(token) is None
    _, fresh_token, _ = store.login("secure_owner", "owner password long enough")
    assert store.resolve_session(fresh_token)["userId"] == owner["userId"]


def test_account_store_honors_explicit_permission_overrides(tmp_path):
    from backend.authorization import PermissionPolicy

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("policy_owner", "owner password long enough")
    support = store.create_managed_account(
        owner["userId"], "policy_support", "support password long enough", "support"
    )
    policy = PermissionPolicy(tmp_path / "accounts.sqlite3")
    policy.set_override("owner", support["userId"], "accounts.create", "allow")
    created = store.create_managed_account(
        support["userId"], "support_created", "created password long enough", "user"
    )
    assert created["role"] == "user"

    policy.set_override("owner", support["userId"], "accounts.create", "deny")
    with pytest.raises(AccountError, match="Permesso di creazione"):
        store.create_managed_account(
            support["userId"], "support_denied", "created password long enough", "user"
        )


def test_owner_totp_pending_enrollment_expires_after_ten_minutes(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from backend.totp import code_at
    import time
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)

    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("pending_owner", "owner password long enough")
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    with store._connect() as db:
        db.execute(
            "UPDATE accounts SET totp_pending_created_at=? WHERE user_id=?",
            (int(time.time()) - 601, owner["userId"]),
        )
    with pytest.raises(AccountError, match="scaduta"):
        store.confirm_totp_setup(owner["userId"], code_at(secret, int(time.time())))
    assert store.totp_enabled(owner["userId"]) is False


def test_account_search_is_bounded_and_matches_username_or_id(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    first = store.register("search_alpha", "search alpha password long")
    store.register("search_beta", "search beta password long")
    assert [item["username"] for item in store.list_accounts(100, "ALPHA")] == ["search_alpha"]
    assert [item["userId"] for item in store.list_accounts(100, first["userId"])] == [first["userId"]]
    assert len(store.list_accounts(1, "")) == 1


def test_login_success_audit_detects_new_client_network_without_raw_ip(tmp_path):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("network_owner", "owner password long enough")

    assert store.record_login_success(owner["userId"], "owner", "203.0.113.10") is True
    assert store.record_login_success(owner["userId"], "owner", "203.0.113.10") is False
    assert store.record_login_success(owner["userId"], "owner", "198.51.100.20") is True

    events = store.list_audit_events(10)
    login_events = [event for event in events if event["action"] == "auth.login_success"]
    assert len(login_events) == 3
    assert login_events[0]["details"]["newIp"] is True
    assert "198.51.100.20" not in str(login_events)
    assert len(login_events[0]["details"]["ipHash"]) == 64
