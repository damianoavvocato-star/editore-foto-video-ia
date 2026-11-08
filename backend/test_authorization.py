import pytest

from backend.authorization import (
    PERMISSIONS, ROLE_DEFAULTS, PermissionError, PermissionPolicy,
)


def test_role_defaults_are_least_privilege_and_known():
    assert ROLE_DEFAULTS["owner"] == PERMISSIONS
    assert "billing.grant" not in ROLE_DEFAULTS["admin"]
    assert ROLE_DEFAULTS["support"].isdisjoint({"accounts.create", "settings.manage"})
    assert ROLE_DEFAULTS["user"] == frozenset()


def test_unknown_roles_and_permissions_fail_closed(tmp_path):
    policy = PermissionPolicy(tmp_path / "permissions.sqlite3")
    assert policy.has_permission("u1", "unknown", "accounts.read") is False
    assert policy.has_permission("u1", "admin", "unknown.permission") is False


def test_owner_can_override_and_deny_takes_precedence(tmp_path):
    policy = PermissionPolicy(tmp_path / "permissions.sqlite3")
    policy.set_override("owner", "u1", "billing.grant", "allow")
    assert policy.has_permission("u1", "support", "billing.grant") is True
    policy.set_override("owner", "u1", "billing.grant", "deny")
    assert policy.has_permission("u1", "admin", "accounts.create") is True
    assert policy.has_permission("u1", "support", "billing.grant") is False
    assert policy.remove_override("owner", "u1", "billing.grant") is True
    assert policy.has_permission("u1", "support", "billing.grant") is False


def test_non_owner_cannot_change_permissions(tmp_path):
    policy = PermissionPolicy(tmp_path / "permissions.sqlite3")
    with pytest.raises(PermissionError):
        policy.set_override("admin", "u1", "accounts.create", "allow")
    with pytest.raises(PermissionError):
        policy.remove_override("support", "u1", "accounts.read")


def test_owner_can_review_permission_overrides_and_effective_set(tmp_path):
    policy = PermissionPolicy(tmp_path / "permissions.sqlite3")
    policy.set_override("owner", "support1", "billing.read", "deny")
    policy.set_override("owner", "support1", "accounts.read", "allow")
    assert policy.list_overrides("owner", "support1")[0]["permission"] == "accounts.read"
    assert "accounts.read" in policy.effective_permissions("support1", "support")
    assert "billing.read" not in policy.effective_permissions("support1", "support")
    with pytest.raises(PermissionError):
        policy.list_overrides("admin", "support1")
