"""Tests for the fail-closed Studio worker lifecycle."""
import uuid

from backend.entitlements import EntitlementStore
from backend.studio import StudioJobRequest
from backend.studio_queue import StudioJobQueue
from backend.studio_worker import StudioWorker
from backend.usage_store import UsageStore


class FakeProvider:
    configured = True
    test_mode = True

    def __init__(self, fail=False):
        self.calls = []
        self.fail = fail
        self.status = "in_progress"
        self.retrievals = []
        self.fail_retrieval = False

    def create_video(self, request, callback_id=None):
        self.calls.append((request, callback_id))
        if self.fail:
            raise RuntimeError("connection lost after request submission")
        return {"providerVideoId": str(uuid.uuid4()), "providerStatus": "in_progress"}

    def retrieve_video(self, video_id):
        self.retrievals.append(video_id)
        if self.fail_retrieval:
            raise RuntimeError("temporary provider status error")
        return {
            "providerVideoId": video_id,
            "providerStatus": self.status,
            "downloadUrl": "https://temporary.example/private-video.mp4",
        }


def _worker(tmp_path, request, *, consent_verifier=None, provider=None, reserve=True):
    accounts_db = tmp_path / "accounts.sqlite3"
    queue = StudioJobQueue(tmp_path / "queue.sqlite3")
    entitlements = EntitlementStore(accounts_db)
    usage = UsageStore(accounts_db)
    draft_id = "a" * 32
    queued, _ = queue.enqueue(
        "user-a", request, idempotency_key=f"studio-draft:{draft_id}"
    )
    if reserve:
        usage.reserve("user-a", f"studio-{draft_id}", 10)
    worker = StudioWorker(
        "worker-test", queue, entitlements, usage,
        provider or FakeProvider(),
        consent_verifier=consent_verifier,
        quota_limit=lambda is_premium: 100 if is_premium else 10,
    )
    return worker, queue, queued


def test_worker_submits_only_authorized_reserved_reviewed_job(tmp_path):
    worker, queue, queued = _worker(
        tmp_path, StudioJobRequest(task="script_to_video", script="Reviewed script")
    )
    result = worker.process_once()
    assert result["jobId"] == queued["jobId"]
    assert result["state"] == "processing"
    assert len(worker.provider.calls) == 1
    assert worker.provider.calls[0][1] == queued["jobId"]
    assert queue.get("user-a", queued["jobId"])["state"] == "processing"


def test_worker_fails_closed_when_quota_reservation_is_missing(tmp_path):
    provider = FakeProvider()
    worker, queue, queued = _worker(
        tmp_path, StudioJobRequest(task="script_to_video", script="Reviewed script"),
        provider=provider, reserve=False,
    )
    result = worker.process_once()
    assert result["state"] == "failed"
    assert result["lastErrorCode"] == "quota_reservation_missing"
    assert provider.calls == []


def test_worker_requires_verified_consent_for_personal_avatar(tmp_path):
    provider = FakeProvider()
    request = StudioJobRequest(
        task="script_to_video", script="Reviewed script",
        avatarMode="personal", avatarConsent=True,
    )
    worker, queue, queued = _worker(tmp_path, request, provider=provider)
    result = worker.process_once()
    assert result["state"] == "failed"
    assert result["lastErrorCode"] == "consent_not_verified"
    assert provider.calls == []


def test_worker_accepts_personal_avatar_only_after_consent_verifier(tmp_path):
    request = StudioJobRequest(
        task="script_to_video", script="Reviewed script",
        avatarMode="personal", avatarConsent=True,
    )
    provider = FakeProvider()
    worker, queue, queued = _worker(
        tmp_path, request, provider=provider,
        consent_verifier=lambda user_id, value: user_id == "user-a" and value.avatarConsent,
    )
    result = worker.process_once()
    assert result["state"] == "processing"
    assert len(provider.calls) == 1


def test_worker_never_retries_ambiguous_provider_submission(tmp_path):
    provider = FakeProvider(fail=True)
    worker, queue, queued = _worker(
        tmp_path, StudioJobRequest(task="script_to_video", script="Reviewed script"),
        provider=provider,
    )
    result = worker.process_once()
    assert result["state"] == "failed"
    assert result["lastErrorCode"] == "submission_outcome_unknown"
    assert queue.claim_next("second-worker") is None
    assert len(provider.calls) == 1


def test_worker_requires_both_explicit_switches_for_paid_provider_mode(tmp_path, monkeypatch):
    provider = FakeProvider()
    provider.test_mode = False
    monkeypatch.delenv("SYNTHESIA_TEST_MODE", raising=False)
    monkeypatch.setenv("SYNTHESIA_ALLOW_PAID_GENERATION", "true")
    worker, queue, queued = _worker(
        tmp_path, StudioJobRequest(task="script_to_video", script="Reviewed script"),
        provider=provider,
    )
    result = worker.process_once()
    assert result["state"] == "failed"
    assert result["lastErrorCode"] == "paid_provider_mode_disabled"
    assert provider.calls == []


def test_worker_reconciles_provider_completion_without_persisting_download_url(tmp_path):
    provider = FakeProvider()
    worker, queue, queued = _worker(
        tmp_path, StudioJobRequest(task="script_to_video", script="Reviewed script"),
        provider=provider,
    )
    submitted = worker.process_once()
    assert submitted["state"] == "processing"
    provider.status = "complete"
    result = worker.reconcile_once()
    assert result["state"] == "completed"
    assert result["providerStatus"] == "complete"
    assert provider.retrievals == [submitted["providerVideoId"]]
    assert "downloadUrl" not in result


def test_worker_keeps_job_processing_when_provider_status_is_temporarily_unavailable(tmp_path):
    provider = FakeProvider()
    worker, queue, queued = _worker(
        tmp_path, StudioJobRequest(task="script_to_video", script="Reviewed script"),
        provider=provider,
    )
    submitted = worker.process_once()
    provider.fail_retrieval = True
    result = worker.reconcile_once()
    assert result["state"] == "processing"
    assert result["reconciled"] is False
    assert result["errorCode"] == "provider_status_unavailable"
    assert queue.get("user-a", queued["jobId"])["state"] == "processing"
