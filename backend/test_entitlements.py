import pytest

from backend.entitlements import EntitlementError, EntitlementStore


def test_owner_grants_expiring_premium_and_revokes(tmp_path):
    store = EntitlementStore(tmp_path / "entitlements.sqlite3")
    now = 1_900_000_000
    grant = store.grant("owner", "owner1", "user1", "premium", now + 60, "beta tester")
    assert store.has_premium("user1", now)
    assert not store.has_premium("user1", now + 60)
    assert store.revoke("owner", grant)
    assert not store.has_premium("user1", now)


def test_non_owner_cannot_grant_or_revoke(tmp_path):
    store = EntitlementStore(tmp_path / "entitlements.sqlite3")
    with pytest.raises(EntitlementError):
        store.grant("admin", "admin1", "user1", "premium")
    grant = store.grant("owner", "owner1", "user1", "premium")
    with pytest.raises(EntitlementError):
        store.revoke("support", grant)


def test_family_members_inherit_active_family_grant_and_seat_limit(tmp_path):
    store = EntitlementStore(tmp_path / "entitlements.sqlite3")
    family = store.create_family("family_owner", seat_limit=2)
    store.grant("owner", "platform_owner", "family_owner", "family")
    store.add_family_member(family, "family_owner", "member1")
    assert store.has_premium("member1")
    with pytest.raises(EntitlementError, match="posti"):
        store.add_family_member(family, "family_owner", "member2")


def test_non_family_member_cannot_add_seats(tmp_path):
    store = EntitlementStore(tmp_path / "entitlements.sqlite3")
    family = store.create_family("family_owner")
    with pytest.raises(EntitlementError):
        store.add_family_member(family, "intruder", "member1")
