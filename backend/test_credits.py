import pytest

from backend.credits import CreditError, CreditStore


def test_owner_grant_and_idempotent_consumption(tmp_path):
    store = CreditStore(tmp_path / "accounts.sqlite3")
    grant = store.grant("owner", "owner-1", "user-1", 100, "grant-1", "beta credits")
    assert grant["balance"] == 100
    repeated_grant = store.grant("owner", "owner-1", "user-1", 100, "grant-1", "beta credits")
    assert repeated_grant["applied"] is False
    assert repeated_grant["balance"] == 100

    charge = store.consume("user-1", 30, "job-1")
    assert charge["balance"] == 70
    repeated_charge = store.consume("user-1", 30, "job-1")
    assert repeated_charge["applied"] is False
    assert repeated_charge["balance"] == 70


def test_credit_ledger_prevents_negative_balance_and_key_reuse(tmp_path):
    store = CreditStore(tmp_path / "accounts.sqlite3")
    store.grant("owner", "owner-1", "user-1", 10, "grant-1", "test")
    with pytest.raises(CreditError, match="insufficienti"):
        store.consume("user-1", 11, "job-1")
    store.consume("user-1", 5, "job-1")
    with pytest.raises(CreditError, match="quantità diversa"):
        store.consume("user-1", 4, "job-1")
    assert store.balance("user-1")["balance"] == 5


def test_refund_is_bounded_by_original_charge_and_idempotent(tmp_path):
    store = CreditStore(tmp_path / "accounts.sqlite3")
    store.grant("owner", "owner-1", "user-1", 20, "grant-1", "test")
    store.consume("user-1", 12, "job-1")
    refund = store.refund("user-1", 12, "job-1")
    assert refund["balance"] == 20
    repeated = store.refund("user-1", 12, "job-1")
    assert repeated["applied"] is False
    with pytest.raises(CreditError, match="superiore"):
        store.refund("user-1", 1, "job-1")


def test_only_owner_can_grant_and_history_is_user_scoped(tmp_path):
    store = CreditStore(tmp_path / "accounts.sqlite3")
    with pytest.raises(CreditError):
        store.grant("admin", "admin-1", "user-1", 5, "grant-1", "test")
    store.grant("owner", "owner-1", "user-1", 5, "grant-1", "test")
    assert store.history("user-1")[0]["kind"] == "grant"
    assert store.history("user-2") == []
