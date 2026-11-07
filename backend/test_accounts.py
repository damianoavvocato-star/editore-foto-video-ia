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
