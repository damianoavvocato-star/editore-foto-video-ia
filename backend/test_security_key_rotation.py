import pytest
from cryptography.fernet import Fernet, InvalidToken

from backend.accounts import AccountStore, SecurityConfigurationError
from backend.security_key_rotation import rotate_totp_encryption_key


def test_totp_key_rotation_reencrypts_active_and_pending_secrets(tmp_path, monkeypatch):
    old_key = Fernet.generate_key()
    new_key = Fernet.generate_key()
    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", old_key.decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("rotate_owner", "owner password long enough")
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    old_cipher = Fernet(old_key)
    with store._connect() as db:
        db.execute(
            """UPDATE accounts SET totp_secret_enc=?,totp_enabled_at=1
               WHERE user_id=?""",
            (old_cipher.encrypt(b"ACTIVESEED"), owner["userId"]),
        )
        before = db.execute(
            """SELECT totp_secret_enc,totp_pending_secret_enc FROM accounts
               WHERE user_id=?""",
            (owner["userId"],),
        ).fetchone()

    assert rotate_totp_encryption_key(store.database, old_key, new_key) == 1
    with store._connect() as db:
        after = db.execute(
            """SELECT totp_secret_enc,totp_pending_secret_enc FROM accounts
               WHERE user_id=?""",
            (owner["userId"],),
        ).fetchone()
    new_cipher = Fernet(new_key)
    assert bytes(before["totp_secret_enc"]) != bytes(after["totp_secret_enc"])
    assert bytes(before["totp_pending_secret_enc"]) != bytes(after["totp_pending_secret_enc"])
    assert new_cipher.decrypt(after["totp_secret_enc"]) == b"ACTIVESEED"
    assert new_cipher.decrypt(after["totp_pending_secret_enc"]) == secret.encode("ascii")


def test_totp_key_rotation_rolls_back_if_old_key_is_wrong(tmp_path):
    old_key = Fernet.generate_key()
    wrong_key = Fernet.generate_key()
    new_key = Fernet.generate_key()
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("rotate_owner", "owner password long enough")
    monkeypatch_key = old_key.decode("ascii")
    import os
    os.environ["MEDIA_TOTP_ENCRYPTION_KEY"] = monkeypatch_key
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    with store._connect() as db:
        before = db.execute(
            "SELECT totp_pending_secret_enc FROM accounts WHERE user_id=?",
            (owner["userId"],),
        ).fetchone()["totp_pending_secret_enc"]

    with pytest.raises(SecurityConfigurationError):
        rotate_totp_encryption_key(store.database, wrong_key, new_key)

    with store._connect() as db:
        after = db.execute(
            "SELECT totp_pending_secret_enc FROM accounts WHERE user_id=?",
            (owner["userId"],),
        ).fetchone()["totp_pending_secret_enc"]
    assert bytes(after) == bytes(before)
    assert Fernet(old_key).decrypt(after) == secret.encode("ascii")
