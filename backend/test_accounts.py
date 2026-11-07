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
