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
