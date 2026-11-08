import pytest

from backend.accounts import AccountStore
from backend.entitlements import EntitlementStore
from backend.referrals import ReferralError, ReferralStore


def _accounts(path):
    store = AccountStore(path)
    inviter = store.register("ref_inviter", "inviter password long enough")
    invitee = store.register("ref_invitee", "invitee password long enough")
    other = store.register("ref_other", "other password long enough")
    return store, inviter["userId"], invitee["userId"], other["userId"]


def test_referral_code_is_stable_and_claim_waits_for_maturation(tmp_path):
    database = tmp_path / "accounts.sqlite3"
    _, inviter, invitee, _ = _accounts(database)
    referrals = ReferralStore(database)

    code = referrals.create_or_get_code(inviter)
    assert referrals.create_or_get_code(inviter) == code
    claim = referrals.claim(invitee, code, now=2_000_000_000)

    assert claim["status"] == "pending"
    assert claim["rewardDays"] == 30
    assert referrals.mature_due(now=2_000_000_000) == 0
    assert EntitlementStore(database).has_premium(inviter, 2_000_000_000) is False
    assert EntitlementStore(database).has_premium(invitee, 2_000_000_000) is False


def test_referral_rewards_both_accounts_once_after_seven_days(tmp_path):
    database = tmp_path / "accounts.sqlite3"
    _, inviter, invitee, _ = _accounts(database)
    referrals = ReferralStore(database)
    code = referrals.create_or_get_code(inviter)
    now = 2_000_000_000
    referrals.claim(invitee, code, now=now)

    mature_at = now + ReferralStore.MATURATION_SECONDS
    assert referrals.mature_due(now=mature_at) == 1
    assert referrals.mature_due(now=mature_at + 1) == 0
    entitlements = EntitlementStore(database)
    assert entitlements.has_premium(inviter, mature_at)
    assert entitlements.has_premium(invitee, mature_at)
    assert not entitlements.has_premium(inviter, mature_at + ReferralStore.REWARD_SECONDS)
    history = referrals.history(inviter, now=mature_at)
    assert history["claims"][0]["status"] == "rewarded"
    assert history["claims"][0]["rewardDays"] == 30


def test_referral_rejects_self_claim_and_second_claim_for_invitee(tmp_path):
    database = tmp_path / "accounts.sqlite3"
    _, inviter, invitee, other = _accounts(database)
    referrals = ReferralStore(database)
    inviter_code = referrals.create_or_get_code(inviter)
    other_code = referrals.create_or_get_code(other)

    with pytest.raises(ReferralError, match="stesso codice"):
        referrals.claim(inviter, inviter_code)
    referrals.claim(invitee, inviter_code)
    with pytest.raises(ReferralError, match="già utilizzato"):
        referrals.claim(invitee, other_code)


def test_referral_rejects_unknown_code_and_inactive_accounts(tmp_path):
    database = tmp_path / "accounts.sqlite3"
    accounts, inviter, invitee, _ = _accounts(database)
    referrals = ReferralStore(database)
    with pytest.raises(ReferralError, match="inesistente"):
        referrals.claim(invitee, "UNKNOWN1")
    code = referrals.create_or_get_code(inviter)
    with accounts._connect() as db:
        db.execute("UPDATE accounts SET disabled_at=1 WHERE user_id=?", (invitee,))
    with pytest.raises(ReferralError, match="attivi"):
        referrals.claim(invitee, code)


def test_referral_history_is_scoped_to_the_signed_in_account(tmp_path):
    database = tmp_path / "accounts.sqlite3"
    _, inviter, invitee, _ = _accounts(database)
    referrals = ReferralStore(database)
    code = referrals.create_or_get_code(inviter)
    referrals.claim(invitee, code, now=2_000_000_000)

    inviter_history = referrals.history(inviter, now=2_000_000_000)
    invitee_history = referrals.history(invitee, now=2_000_000_000)
    assert inviter_history["code"] == code
    assert inviter_history["claims"][0]["role"] == "inviter"
    assert invitee_history["code"] is None
    assert invitee_history["claims"][0]["role"] == "invitee"
