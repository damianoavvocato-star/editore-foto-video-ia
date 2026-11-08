"""Fail-closed worker for explicitly reviewed Studio queue jobs.

The worker is not started by the API process. Deployments must run it as a
separate supervised service and provide a verified consent callback for personal
avatars or cloned voices.
"""
from __future__ import annotations

import os
import re
from collections.abc import Callable
from typing import Any

from backend.entitlements import EntitlementStore
from backend.studio import StudioJobRequest, StudioRequestError
from backend.studio_provider import SynthesiaVideoProvider
from backend.studio_queue import StudioJobQueue, StudioQueueError
from backend.usage_store import UsageStore


DRAFT_KEY_PATTERN = re.compile(r"^studio-draft:([0-9a-f]{32})$")


class StudioWorkerError(RuntimeError):
    """Worker configuration or authorization failure."""


class StudioWorker:
    """Processes one queued job with entitlement, quota and consent rechecks."""

    def __init__(
        self,
        worker_id: str,
        queue: StudioJobQueue,
        entitlements: EntitlementStore,
        usage: UsageStore,
        provider: SynthesiaVideoProvider,
        consent_verifier: Callable[[str, StudioJobRequest], bool] | None = None,
        quota_limit: Callable[[bool], int] | None = None,
    ) -> None:
        if not worker_id or len(worker_id) > 128:
            raise StudioWorkerError("Identificativo worker non valido.")
        self.worker_id = worker_id
        self.queue = queue
        self.entitlements = entitlements
        self.usage = usage
        self.provider = provider
        self.consent_verifier = consent_verifier or (lambda _user, _request: False)
        self.quota_limit = quota_limit or self._configured_quota_limit

    @staticmethod
    def _configured_quota_limit(is_premium: bool) -> int:
        name = "MEDIA_PREMIUM_AI_MONTHLY_LIMIT" if is_premium else "MEDIA_FREE_AI_MONTHLY_LIMIT"
        default = 100 if is_premium else 10
        raw = os.getenv(name)
        try:
            limit = default if raw is None else int(raw)
        except (TypeError, ValueError) as exc:
            raise StudioWorkerError("Configurazione quota mensile non valida.") from exc
        if not 1 <= limit <= 100000:
            raise StudioWorkerError("Configurazione quota mensile non valida.")
        return limit

    def _fail(self, job_id: str, code: str) -> dict[str, Any]:
        return self.queue.fail_claimed(self.worker_id, job_id, code)

    def process_once(self) -> dict[str, Any]:
        """Claim and process at most one job; never auto-retry an ambiguous submit."""
        claimed = self.queue.claim_next(self.worker_id)
        if claimed is None:
            return {"claimed": False, "state": "idle"}

        job_id = claimed["jobId"]
        context = claimed.get("_worker") or {}
        user_id = context.get("userId")
        idempotency_key = context.get("idempotencyKey") or ""
        key_match = DRAFT_KEY_PATTERN.fullmatch(idempotency_key)
        if not user_id or key_match is None:
            return self._fail(job_id, "queue_context_invalid")

        try:
            request = StudioJobRequest.model_validate(claimed["request"])
            request.validate_policy()
        except (ValueError, StudioRequestError):
            return self._fail(job_id, "request_policy_invalid")

        is_premium = self.entitlements.has_premium(user_id)
        try:
            limit = self.quota_limit(is_premium)
        except StudioWorkerError:
            return self._fail(job_id, "quota_configuration_invalid")

        reservation_id = f"studio-{key_match.group(1)}"
        try:
            reserved = self.usage.has_reservation(user_id, reservation_id, limit)
        except (ValueError, OSError):
            reserved = False
        if not reserved:
            return self._fail(job_id, "quota_reservation_missing")

        requires_special_consent = (
            request.avatarMode == "personal" or request.voiceMode == "clone"
        )
        if requires_special_consent:
            try:
                consent_verified = self.consent_verifier(user_id, request) is True
            except Exception:
                consent_verified = False
            if not consent_verified:
                return self._fail(job_id, "consent_not_verified")

        if not getattr(self.provider, "configured", False):
            return self._fail(job_id, "provider_not_configured")

        # The adapter factory also enforces this, but the worker repeats the
        # gate so a directly constructed provider cannot accidentally enable
        # billable generation without both explicit environment switches.
        if not getattr(self.provider, "test_mode", True):
            if (
                os.getenv("SYNTHESIA_TEST_MODE", "true").strip().lower() != "false"
                or os.getenv("SYNTHESIA_ALLOW_PAID_GENERATION", "").strip().lower() != "true"
            ):
                return self._fail(job_id, "paid_provider_mode_disabled")

        # These tasks are not implemented by the current Synthesia adapter.
        if request.task not in {"script_to_video", "avatar_video", "bulk_personalization"}:
            return self._fail(job_id, "provider_task_unsupported")

        try:
            result = self.provider.create_video(request, callback_id=job_id)
        except Exception:
            # The provider may have accepted the request before the connection failed.
            # Never retry this automatically: reconcile callback/provider state first.
            return self._fail(job_id, "submission_outcome_unknown")

        try:
            return self.queue.mark_submitted(
                self.worker_id,
                job_id,
                result["providerVideoId"],
                result.get("providerStatus", "in_progress"),
            )
        except (KeyError, StudioQueueError):
            # If the lease expired or the response was malformed, a later reconciler
            # must determine whether the provider accepted the request.
            return self._fail(job_id, "submission_outcome_unknown")


    def reconcile_once(self) -> dict[str, Any]:
        """Poll one accepted provider job and persist only its validated status.

        Provider download URLs are intentionally discarded here. A later
        delivery stage must copy completed media into controlled object storage
        before exposing a user-download URL.
        """
        job = self.queue.claim_reconciliation(self.worker_id)
        if job is None:
            return {"claimed": False, "state": "idle"}
        job_id = job["jobId"]
        context = job.get("_worker") or {}
        user_id = context.get("userId")
        token = context.get("reconciliationToken")
        provider_video_id = job.get("providerVideoId")
        if not user_id or not provider_video_id or not token:
            return {"jobId": job_id, "state": "processing", "reconciled": False,
                    "errorCode": "reconciliation_context_invalid"}
        try:
            remote = self.provider.retrieve_video(provider_video_id)
            status = remote.get("providerStatus")
            if remote.get("providerVideoId") != provider_video_id:
                raise ValueError("Provider returned a mismatched video identifier.")
        except Exception:
            # Release the lease so a later supervisor can retry this read.
            self.queue.release_reconciliation(job_id, token)
            return {"jobId": job_id, "state": "processing", "reconciled": False,
                    "errorCode": "provider_status_unavailable"}
        try:
            return self.queue.record_provider_status(
                user_id, job_id, status, reconciliation_token=token
            )
        except (StudioQueueError, ValueError):
            # A stale reconciler cannot overwrite a newer worker's result.
            latest = self.queue.get(user_id, job_id)
            if latest is not None and latest["state"] in {"completed", "failed"}:
                return latest
            return {"jobId": job_id, "state": "processing", "reconciled": False,
                    "errorCode": "provider_status_update_conflict"}
