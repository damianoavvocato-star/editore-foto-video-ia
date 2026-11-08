import concurrent.futures
import sqlite3

import pytest

from backend.usage_store import UsageLimitError, UsageStore


def test_monthly_usage_is_account_scoped_and_resets_next_month(tmp_path):
    store = UsageStore(tmp_path / "accounts.sqlite3")
    first = store.reserve("user-a", "job-1", 2, now=1_800_000_000)
    second = store.reserve("user-a", "job-2", 2, now=1_800_000_000)
    other_user = store.reserve("user-b", "job-1", 2, now=1_800_000_000)
    next_month = store.reserve("user-a", "job-3", 2, now=1_802_700_000)

    assert first["used"] == 1
    assert second["used"] == 2
    assert second["remaining"] == 0
    assert other_user["used"] == 1
    assert next_month["period"] != second["period"]
    assert next_month["used"] == 1


def test_monthly_usage_rejects_requests_after_limit(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    store.reserve("user-a", "job-1", 1, now=1_800_000_000)

    with pytest.raises(UsageLimitError) as error:
        store.reserve("user-a", "job-2", 1, now=1_800_000_000)

    assert error.value.limit == 1


def test_monthly_usage_reservation_is_idempotent_for_same_job(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    first = store.reserve("user-a", "job-1", 2, now=1_800_000_000)
    repeated = store.reserve("user-a", "job-1", 2, now=1_800_000_000)

    assert first == repeated


def test_concurrent_reservations_never_exceed_limit(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    def reserve(index):
        try:
            return store.reserve("user-a", f"job-{index}", 3, now=1_800_000_000)
        except UsageLimitError:
            return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(reserve, range(12)))

    assert sum(result is not None for result in results) == 3
    with sqlite3.connect(store.database) as db:
        count = db.execute(
            "SELECT COUNT(*) FROM ai_usage_reservations WHERE user_id='user-a'"
        ).fetchone()[0]
    assert count == 3


def test_usage_database_is_private(tmp_path):
    import os
    import stat

    if os.name != "posix":
        return
    database = tmp_path / "usage.sqlite3"
    UsageStore(database)
    assert stat.S_IMODE(database.stat().st_mode) == 0o600


def test_failed_job_acceptance_can_release_exact_quota_reservation(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    reservation = store.reserve("user-a", "job-1", 1, now=1_800_000_000)

    assert store.release("user-a", "job-1", reservation["period"]) is True
    assert store.release("user-a", "job-1", reservation["period"]) is False

    next_job = store.reserve("user-a", "job-2", 1, now=1_800_000_000)
    assert next_job["used"] == 1
    assert next_job["remaining"] == 0


def test_quota_release_is_scoped_to_account_and_period(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    first = store.reserve("user-a", "job-1", 2, now=1_800_000_000)
    store.reserve("user-b", "job-1", 2, now=1_800_000_000)

    assert store.release("user-a", "job-1", first["period"]) is True
    assert store.reserve("user-a", "job-2", 2, now=1_800_000_000)["used"] == 1
    assert store.reserve("user-b", "job-2", 2, now=1_800_000_000)["used"] == 2


def test_concurrent_reservations_across_store_instances_never_exceed_limit(tmp_path):
    database = tmp_path / "shared-accounts.sqlite3"
    stores = [UsageStore(database) for _ in range(4)]

    def reserve(index):
        try:
            return stores[index % len(stores)].reserve(
                "shared-user", f"parallel-job-{index}", 2, now=1_800_000_000
            )
        except UsageLimitError:
            return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(reserve, range(24)))

    assert sum(result is not None for result in results) == 2
    with sqlite3.connect(database) as db:
        count = db.execute(
            "SELECT COUNT(*) FROM ai_usage_reservations WHERE user_id=?",
            ("shared-user",),
        ).fetchone()[0]
    assert count == 2


def test_quota_release_is_visible_across_store_instances(tmp_path):
    database = tmp_path / "shared-accounts.sqlite3"
    reserver = UsageStore(database)
    releaser = UsageStore(database)
    second_request = UsageStore(database)

    reservation = reserver.reserve(
        "shared-user", "job-first", 1, now=1_800_000_000
    )
    assert releaser.release(
        "shared-user", "job-first", reservation["period"]
    ) is True

    replacement = second_request.reserve(
        "shared-user", "job-second", 1, now=1_800_000_000
    )
    assert replacement["used"] == 1
    assert replacement["remaining"] == 0


def test_reservation_validation_checks_original_month_and_current_limit(tmp_path):
    store = UsageStore(tmp_path / "accounts.sqlite3")
    store.reserve("user-a", "studio-draft-1", 3, now=1_800_000_000)
    assert store.has_reservation("user-a", "studio-draft-1", 3) is True
    assert store.has_reservation("user-a", "studio-draft-1", 2) is True
    assert store.has_reservation("user-a", "missing", 3) is False
    store.reserve("user-a", "studio-draft-2", 3, now=1_800_000_000)
    store.reserve("user-a", "studio-draft-3", 3, now=1_800_000_000)
    store.reserve("user-a", "studio-draft-4", 4, now=1_800_000_000)
    assert store.has_reservation("user-a", "studio-draft-1", 2) is False


def test_usage_summary_reports_remaining_and_exhaustion(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    store.reserve("user-a", "job-1", 2, now=1_800_000_000)
    summary = store.summary("user-a", 2, now=1_800_000_000)
    assert summary["used"] == 1
    assert summary["limit"] == 2
    assert summary["remaining"] == 1
    assert summary["exhausted"] is False

    store.reserve("user-a", "job-2", 2, now=1_800_000_000)
    exhausted = store.summary("user-a", 2, now=1_800_000_000)
    assert exhausted["remaining"] == 0
    assert exhausted["exhausted"] is True


def test_usage_summary_is_scoped_to_user_and_validates_limit(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3")
    store.reserve("user-a", "job-1", 2, now=1_800_000_000)
    assert store.summary("user-b", 2, now=1_800_000_000)["used"] == 0
    with pytest.raises(ValueError):
        store.summary("user-a", 0, now=1_800_000_000)
