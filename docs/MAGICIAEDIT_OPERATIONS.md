# MagicIAedit cloud operations

MagicIAedit is a review-first planning service. It analyses media already uploaded
to the media API and returns an editable timeline proposal. The client does not
apply the proposal until the user explicitly approves it.

## Server configuration

Configure these values in the backend deployment secret manager, never in
Flutter settings, source control, logs, or a client build:

- `MAGICIA_API_BASE_URL`: HTTPS base URL of an OpenAI-compatible vision API.
  The service appends `/chat/completions`.
- `MAGICIA_API_KEY`: provider credential.
- `MAGICIA_MODEL`: vision-capable model identifier.
- `FFMPEG_PATH` and `FFPROBE_PATH`: optional executable paths when the
  binaries are not available on PATH.

The provider is considered configured only when all three provider variables
are present and the base URL starts with HTTPS. Until then, the authenticated
AI job endpoint returns HTTP 503 and no provider request is attempted. Do not
put the provider key in the app, a Dart define, or an API response.

The Flutter client separately needs the media API origin configured for its
environment. Use the account's normal authenticated session; do not create a
shared, long-lived client token for MagicIAedit.

## Resource limits

The current service enforces the following bounds before provider submission:

| Resource | Limit |
| --- | ---: |
| Selected photos/videos | 20 |
| One image file | 20 MB |
| One video file | 100 MB |
| Combined media selection | 400 MB |
| Decoded image pixels | 25 million |
| Images sent per vision frame | 4 MB |
| Generated timeline clips | 24 |
| Provider response read | 8 MB |

Supported image formats are JPG/JPEG, PNG and WebP. Supported video formats are
MP4, MOV, AVI, WebM and M4V. Audio-only files are not accepted by MagicIAedit.
Video analysis samples up to three frames from each clip using FFprobe/FFmpeg.

## Authentication, privacy and cancellation

- AI job creation, polling and cancellation use the media API's normal
  authentication and resource-owner checks.
- Media IDs are validated and the model is allowed to reference only IDs from
  the submitted selection.
- Provider redirects are rejected so the Authorization header is not forwarded
  to another host.
- The client receives a proposal for review. It is not applied automatically.
- Cancelling a job sets a server-side cancellation event. Preprocessing checks
  that event between media and video-frame operations. A provider HTTP request
  already in progress is bounded by its request timeout and may take time to
  return; cancellation is checked again before a proposal is accepted.
- Provider response bodies and credentials are not returned in client errors.

## Temporary-file retention

The media backend performs a conservative cleanup during startup:

- `MEDIA_TEMP_RETENTION_HOURS` controls the age threshold (default 24 hours; accepted range 1–720).
- Only incomplete upload files ending in `.part` and inactive per-job work directories are eligible.
- Jobs recorded as queued or rendering are excluded from work-directory cleanup.
- Original uploaded assets and completed exports are never deleted by this startup cleanup.
- This is startup cleanup, not a periodic scheduler. Operators should monitor disk capacity and separately define a retention policy for user assets and exported videos.

The monthly MagicIAedit quota is reserved before job acceptance. If the server cannot register the job's account ownership, the reservation is released; a failed analysis after a job is accepted remains counted as an attempted AI job.

## Operational verification

Before enabling MagicIAedit for production users:

1. Inject the provider variables through the secret manager.
2. Verify the provider URL is HTTPS and points to the intended vision endpoint.
3. Confirm FFmpeg and FFprobe are installed and available to the backend process.
4. Exercise image and video analysis with non-sensitive test media.
5. Verify a user cannot read or cancel another user's job.
6. Verify malformed model output, unknown media IDs, oversized media and
   cancellation are rejected safely.
7. Monitor provider latency, rate limits, data-retention terms and cost per
   generated proposal. Set provider-side spend limits and alert thresholds.

Do not upload confidential or regulated media until the provider's data
processing, retention and regional hosting terms have been reviewed and approved.
