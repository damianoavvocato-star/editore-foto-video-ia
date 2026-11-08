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
