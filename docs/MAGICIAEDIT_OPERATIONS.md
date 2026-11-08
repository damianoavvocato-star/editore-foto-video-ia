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
Video analysis samples up to eight frames from each clip using FFprobe/FFmpeg.

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


## Improved visual reasoning for MagicIAedit

The video analysis stage samples up to eight frames distributed across the full clip
(instead of only the opening, midpoint and ending). Each frame is sent with its actual
timestamp. The backend also calculates small, non-identifying image-quality signals
(brightness, contrast and edge-detail estimates) to help the vision model compare
candidate moments. These are heuristic signals, not face recognition or semantic truth;
the model must still inspect the actual image content. The prompt asks it to avoid
repetitive shots, preserve narrative continuity, select timestamps grounded in sampled
frames and explain clip choices. This increases visual context but also increases
provider token/image cost. Production operators must measure cost and latency with
representative media before increasing limits.


## Creative controls and grounded shot selection

MagicIAedit accepts a strict creative-direction object: preset (balanced, cinematic,
travel, family, social short, product, storytelling, dynamic), pace, aspect ratio,
target duration (5–180 seconds), language and a bounded free-text goal. Unknown values
are rejected before contacting the model. The Flutter panel now exposes style, pace,
aspect ratio and duration controls and sends the device locale as the output-language
hint. These preferences guide the proposal; actual crop/render adaptation and soundtrack
generation remain separate implementation tasks.


## Speech transcription, translation and subtitle foundation

The backend now includes a provider-neutral speech pipeline contract in
`backend/speech_pipeline.py`. It is deliberately separate from the vision-based
MagicIAedit planner:

- Transcription responses are validated for supported language codes, unique
  segment IDs, non-empty text, ordered timestamps and media-duration bounds.
- Translation is matched by stable segment ID. Source timing and speaker
  attribution remain authoritative; a translation provider cannot silently
  shift or omit subtitle intervals.
- SRT and WebVTT export is deterministic and escapes markup-like text.
- A provider adapter is injected server-side. With no adapter configured, speech
  operations fail closed; no network request, paid call, synthetic voice or
  voice clone is attempted by this foundation.

This is a tested backend foundation, not yet an enabled transcription/dubbing
product feature. The next integration step is to connect an approved speech
provider to authenticated media jobs, add audio extraction and review UI, then
add TTS/dubbing and per-language render jobs. Voice cloning must remain disabled
unless the speaker has explicitly provided informed consent. Provider credentials
must stay in the server secret manager.


## Audio extraction for speech jobs

`backend/media_audio.py` adds a local FFmpeg extraction boundary for speech jobs.
It extracts the first audio stream to mono 16 kHz PCM WAV, uses an argument list
(no shell), enforces source/output size and timeout limits, and validates the WAV
signature before returning the destination. Partial files are removed on failures.

The utility is not yet wired to a public upload or job endpoint. The authenticated
worker must first resolve an account-owned media asset to a server-controlled path;
never accept arbitrary client filesystem paths. The deployment must install FFmpeg.
