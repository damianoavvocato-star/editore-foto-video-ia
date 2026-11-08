"""Tests for the durable Studio queue and its safe worker state machine."""
import pytest

from backend.studio import StudioJobRequest
from backend.studio_queue import StudioJobQueue, StudioQueueError


def _request(script="Hello"):
    return StudioJobRequest(task="script_to_video", script=script)


def test_enqueue_is_durable_and_idempotent_per_account(tmp_path):
    path = tmp_path / "queue.sqlite3"
    queue = StudioJobQueue(path)
    first, created = queue.enqueue("user-a", _request(), "key-1", now=100)
    replay, replay_created = queue.enqueue("user-a", _request(), "key-1", now=101)
    assert created is True and replay_created is False
    assert first["jobId"] == replay["jobId"]
    assert first["state"] == "queued"
    reopened = StudioJobQueue(path)
    assert reopened.get("user-a", first["jobId"])["request"]["script"] == "Hello"
    assert reopened.get("user-b", first["jobId"]) is None


def test_idempotency_key_cannot_represent_different_payload(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    queue.enqueue("user-a", _request("First"), "same", now=100)
    with pytest.raises(StudioQueueError, match="idempotenza"):
        queue.enqueue("user-a", _request("Second"), "same", now=101)


def test_claim_is_exclusive_and_lease_owner_is_required(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=30)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    claimed = queue.claim_next("worker-a", now=101)
    assert claimed["jobId"] == job["jobId"]
    assert claimed["attempts"] == 1
    assert queue.claim_next("worker-b", now=102) is None
    with pytest.raises(StudioQueueError, match="lease"):
        queue.mark_submitted("worker-b", job["jobId"], "provider-1", now=103)


def test_successful_submission_and_provider_completion(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("worker-a", now=101)
    submitted = queue.mark_submitted(
        "worker-a", job["jobId"], "video-123", "in_progress", now=102
    )
    assert submitted["state"] == "processing"
    completed = queue.record_provider_status(
        "user-a", job["jobId"], "complete", now=103
    )
    assert completed["state"] == "completed"
    assert completed["providerStatus"] == "complete"
    with pytest.raises(StudioQueueError):
        queue.record_provider_status("user-a", job["jobId"], "error", now=104)


def test_known_pre_acceptance_error_can_retry_with_bounded_attempts(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    job, _ = queue.enqueue("user-a", _request(), max_attempts=2, now=100)
    queue.claim_next("worker-a", now=101)
    retry = queue.schedule_retry(
        "worker-a", job["jobId"], "provider_timeout_before_accept", 10, now=102
    )
    assert retry["state"] == "queued"
    assert retry["nextRetryAt"] == 112
    assert queue.claim_next("worker-b", now=111) is None
    queue.claim_next("worker-b", now=112)
    failed = queue.schedule_retry(
        "worker-b", job["jobId"], "provider_unavailable", 10, now=113
    )
    assert failed["state"] == "failed"
    assert failed["attempts"] == 2


def test_expired_submission_is_failed_not_automatically_replayed(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=15)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("worker-a", now=101)
    assert queue.claim_next("worker-b", now=117) is None
    stored = queue.get("user-a", job["jobId"])
    assert stored["state"] == "failed"
    assert stored["lastErrorCode"] == "submission_outcome_unknown"


def test_provider_status_and_error_code_are_validated(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("worker-a", now=101)
    with pytest.raises(StudioQueueError, match="Stato provider"):
        queue.mark_submitted("worker-a", job["jobId"], "video-1", "mystery", now=102)
    with pytest.raises(StudioQueueError, match="Codice errore"):
        queue.schedule_retry("worker-a", job["jobId"], "API KEY leaked!", now=102)


def test_retry_cannot_be_requested_by_another_worker_or_after_lease(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=15)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("worker-a", now=101)
    with pytest.raises(StudioQueueError):
        queue.schedule_retry("worker-b", job["jobId"], "temporary", now=102)
    with pytest.raises(StudioQueueError):
        queue.schedule_retry("worker-a", job["jobId"], "temporary", now=117)


def test_enqueue_requires_valid_account_and_retry_limit(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    with pytest.raises(StudioQueueError):
        queue.enqueue("", _request())
    with pytest.raises(StudioQueueError):
        queue.enqueue("user-a", _request(), max_attempts=9)



def test_worker_can_renew_only_an_active_lease(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=30)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    claimed = queue.claim_next("worker-a", now=101)
    renewed = queue.renew_lease("worker-a", job["jobId"], now=120)
    assert renewed["leaseExpiresAt"] == 150
    assert renewed["attempts"] == claimed["attempts"] == 1
    with pytest.raises(StudioQueueError, match="Lease"):
        queue.renew_lease("worker-b", job["jobId"], now=121)
    with pytest.raises(StudioQueueError, match="Lease"):
        queue.renew_lease("worker-a", job["jobId"], now=150)


def test_retry_cannot_resurrect_a_submission_after_expiry_reconciliation(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=15)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("worker-a", now=101)
    # The next claimant reconciles an expired submission to terminal/ambiguous.
    assert queue.claim_next("worker-b", now=117) is None
    with pytest.raises(StudioQueueError, match="Lease"):
        queue.schedule_retry("worker-a", job["jobId"], "temporary", now=118)
    assert queue.get("user-a", job["jobId"])["state"] == "failed"


def test_database_permissions_are_private_on_posix(tmp_path):
    import os
    import stat
    import pytest
    if os.name != "posix":
        pytest.skip("POSIX permission bits are not portable")
    database = tmp_path / "private" / "queue.sqlite3"
    StudioJobQueue(database).enqueue("user-a", _request(), now=100)
    assert stat.S_IMODE(database.stat().st_mode) == 0o600
    assert stat.S_IMODE(database.parent.stat().st_mode) == 0o700


def test_list_processing_returns_only_worker_context_for_pending_jobs(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("worker-a", now=101)
    queue.mark_submitted("worker-a", job["jobId"], "provider-video", now=102)
    pending = queue.list_processing()
    assert len(pending) == 1
    assert pending[0]["jobId"] == job["jobId"]
    assert pending[0]["_worker"] == {"userId": "user-a"}
    assert queue.list_for_user("user-a")[0]["state"] == "processing"
    assert "_worker" not in queue.list_for_user("user-a")[0]



def test_reconciliation_lease_is_exclusive_and_expires(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=30)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("submitter", now=101)
    queue.mark_submitted("submitter", job["jobId"], "provider-video", now=102)

    first = queue.claim_reconciliation("reconciler-a", now=103)
    assert first is not None
    assert first["_worker"]["userId"] == "user-a"
    assert queue.claim_reconciliation("reconciler-b", now=104) is None

    assert queue.release_reconciliation(
        job["jobId"], first["_worker"]["reconciliationToken"], now=105
    ) is True
    second = queue.claim_reconciliation("reconciler-b", now=106)
    assert second is not None
    assert second["_worker"]["reconciliationToken"] != first["_worker"]["reconciliationToken"]


def test_stale_reconciliation_token_cannot_update_provider_status(tmp_path):
    queue = StudioJobQueue(tmp_path / "queue.sqlite3", lease_seconds=15)
    job, _ = queue.enqueue("user-a", _request(), now=100)
    queue.claim_next("submitter", now=101)
    queue.mark_submitted("submitter", job["jobId"], "provider-video", now=102)

    stale = queue.claim_reconciliation("reconciler-a", now=103)
    assert stale is not None
    current = queue.claim_reconciliation("reconciler-b", now=119)
    assert current is not None
    with pytest.raises(StudioQueueError, match="Lease"):
        queue.record_provider_status(
            "user-a", job["jobId"], "complete", now=120,
            reconciliation_token=stale["_worker"]["reconciliationToken"],
        )
    updated = queue.record_provider_status(
        "user-a", job["jobId"], "complete", now=120,
        reconciliation_token=current["_worker"]["reconciliationToken"],
    )
    assert updated["state"] == "completed"
