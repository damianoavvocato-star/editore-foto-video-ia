# Studio job orchestration foundation

This increment adds a durable SQLite-backed queue state machine. It is deliberately
provider-neutral and does not expose a public submit endpoint or call Synthesia.

## Lifecycle

- `queued`: validated request persisted and ready for a worker.
- `submitting`: one worker owns a short lease while it attempts provider submission.
- `processing`: provider accepted the request and returned a provider video ID.
- `completed`: provider reports completion.
- `failed`: a terminal provider failure, exhausted known-safe retries, or an
  ambiguous submission outcome requiring reconciliation.

## Safety guarantees

- Jobs are isolated by account ID; reads and listings are account-scoped.
- An account-scoped idempotency key cannot be reused for a different request.
- SQLite `BEGIN IMMEDIATE` serializes claims so two workers cannot claim the same
  queued row at once.
- Worker leases expire; only the lease owner can mark submission or schedule a retry.
- Retries are bounded (1–5 attempts) and delayed (1–3600 seconds).
- Error fields accept only short machine codes, never raw provider response bodies,
  tokens, scripts, or API keys.
- If a worker lease expires while state is `submitting`, the job becomes
  `failed/submission_outcome_unknown`. It is **not** automatically resubmitted:
  the provider may have accepted the first request even if the worker lost its
  response. A future reconciler must query provider callback/job metadata before
  deciding whether a retry is safe.
- No public route calls a paid provider. The existing Synthesia adapter remains
  isolated until account entitlements, consent, quota reservation, provider
  reconciliation, and a real worker lifecycle are integrated.

## Worker integration contract

1. Claim a queued job using a unique worker ID.
2. Persist/record the attempt before making an external request.
3. Use the local job ID as the provider callback/idempotency correlation value.
4. On a confirmed pre-acceptance failure, call `schedule_retry`.
5. On provider acceptance, call `mark_submitted` with the provider video ID.
6. Poll or receive a verified webhook, then call `record_provider_status`.
7. Never blindly retry `submission_outcome_unknown`; reconcile first.

This module is infrastructure groundwork, not a claim that asynchronous video
generation is already available in the app.


## Authenticated API boundary

A reviewed Studio draft can now be explicitly placed into the durable queue with
`POST /v1/studio/jobs/{draft_id}/enqueue`. The endpoint rechecks the account-owned
draft and its media ownership, then derives a stable idempotency key from the
draft ID so repeated taps or network retries cannot create duplicate queue rows.
Queue status is account-scoped through `GET /v1/studio/queue` and
`GET /v1/studio/queue/{queue_job_id}`.

This API operation only persists the request. It does not start a worker, call
Synthesia, reserve paid credits, or claim that a video is rendering. The response
explicitly sets `providerSubmissionEnabled=false`. Provider submission remains
disabled until the entitlement/consent/quota checks and a supervised worker are
implemented.

Workers with longer provider requests can renew an active lease. Retry updates
now include lease owner, state, and expiry in the atomic SQL predicate so an
expired worker cannot resurrect a job after reconciliation. SQLite uses FULL
synchronous mode, and database/WAL/SHM files are restricted to owner-only
permissions where the operating system supports POSIX modes.


## Monthly quota and entitlement enforcement

The authenticated enqueue endpoint now reserves the same account-scoped monthly
AI allowance used by MagicIAedit. Active Premium/family grants are resolved via
the existing entitlement ledger; otherwise the free allowance applies. Defaults
remain aligned with the existing backend policy (10 monthly free requests and
100 Premium requests), configurable with
`MEDIA_FREE_AI_MONTHLY_LIMIT` and `MEDIA_PREMIUM_AI_MONTHLY_LIMIT`.

The reservation key is stable per account and reviewed draft, so a retry does
not consume a second monthly request. Quota exhaustion returns HTTP 429 with
`monthly_ai_quota_exceeded`; if queue persistence rejects the request, the
reservation is released. The queue still does not invoke a video provider:
quota acceptance is not a claim that paid generation has started.


## Supervised worker foundation

A separate `StudioWorker` service can process one queued request at a time.
It is intentionally not started by FastAPI and is not exposed as a public
endpoint. Before calling Synthesia it revalidates the request, account's current
Premium/family entitlement, the original monthly quota reservation, and any
special consent for personal avatars or cloned voices. The default consent
verifier denies those special operations until a real, auditable consent
service is injected.

The worker fails closed when its queue context, quota reservation, configuration,
or provider task is invalid. Provider submission exceptions are treated as
ambiguous and become `submission_outcome_unknown`; they are never blindly
retried because the remote service may already have accepted a billable job.
The current provider adapter supports script/avatar and template jobs only.
Other Studio task types remain queued for a future compatible provider.

The worker is infrastructure code only: no background process is launched by
this commit, no live provider credentials are added, and the default Synthesia
configuration remains test mode.


## Provider status reconciliation

The supervised worker now exposes a one-job-at-a-time `reconcile_once()`
operation. It selects accepted jobs from the internal processing queue, polls
Synthesia through the provider adapter, validates the returned video ID and
status, and atomically advances the local state to `processing`,
`completed`, or `failed`. Temporary provider read failures leave the local
job in `processing` so an external supervisor can retry the status check.

The reconciliation path deliberately discards provider download URLs. They are
temporary provider delivery details and are not copied into account-visible
queue records. A separate controlled object-storage and media-delivery stage
is still required before completed output can be safely downloaded by users.
No polling loop or background service is started by the API process.


## Concurrent reconciliation protection

Provider status polling now uses a separate SQLite reconciliation lease. A
worker must atomically claim a processing job before contacting the provider.
Only the current lease token may persist the result; stale workers cannot
overwrite a newer reconciler's state. Transient provider read failures release
the lease for a later supervised attempt. Expired leases can be reclaimed.
The migration adds the lease columns to existing queue databases without
dropping or rewriting existing jobs.
