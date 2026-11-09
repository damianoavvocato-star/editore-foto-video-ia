# Security operations

## Required production configuration

The owner TOTP secret is encrypted with Fernet. The encryption key is deliberately
kept outside SQLite and outside the repository.

Set `MEDIA_TOTP_ENCRYPTION_KEY` in the backend deployment's secret/environment
manager before enabling owner two-factor authentication. Generate a key in a
trusted administrative environment with:

```sh
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode('ascii'))"
```

Store the generated value in the deployment secret manager. Never put it in
source control, app settings, logs, issue reports, build artifacts, or the
SQLite database. Restrict access to the deployment secret to the backend
runtime and authorized operators. Back up the key separately from the database.
Loss of this key makes encrypted TOTP seeds unreadable; the login endpoint
fails closed with HTTP 503 rather than silently accepting password-only login.

Do not rotate this key by simply replacing the environment value. The
repository includes an atomic offline rotation utility. Back up the account
database and both keys, stop the backend or put it in maintenance mode, then
inject the old and new keys into a protected operator environment using the
deployment secret manager (preferred). For a one-off interactive maintenance
shell, collect key values with hidden input rather than writing them into a
shell command:

```sh
export MEDIA_AUTH_DB=/secure/path/accounts.sqlite3
read -r -s -p "Old TOTP key: " MEDIA_TOTP_OLD_ENCRYPTION_KEY; echo
read -r -s -p "New TOTP key: " MEDIA_TOTP_NEW_ENCRYPTION_KEY; echo
export MEDIA_TOTP_OLD_ENCRYPTION_KEY MEDIA_TOTP_NEW_ENCRYPTION_KEY
python -m backend.security_key_rotation
unset MEDIA_TOTP_OLD_ENCRYPTION_KEY MEDIA_TOTP_NEW_ENCRYPTION_KEY
```

The utility re-encrypts active and pending TOTP seeds in one SQLite transaction,
rolls back if any seed cannot be decrypted, and prints only the number of
updated records. Update the deployment's `MEDIA_TOTP_ENCRYPTION_KEY` to the
new key before restarting the backend. Never place secret values in shell
history, source control, command-line arguments, logs, screenshots, or build
artifacts.

## Mobile account session and media API

The Settings tab includes the account console. Configure its API origin at
build time with `--dart-define=MEDIA_API_URL=https://api.your-domain.example`.
The value must be an HTTPS origin without a path, query, username or password.
For local Android emulator development only, `http://10.0.2.2:8000` is
accepted. Session bearer tokens are stored with platform secure storage and are
reused by remote media export; the old shared media token is not accepted by
authenticated media endpoints.

Accounts created by an administrator receive a temporary password and must
change it before protected application features become available.

## Owner two-factor enrollment

1. Sign in as the owner over HTTPS.
2. Call `GET /v1/owner/security/totp` to inspect enrollment status.
3. Call `POST /v1/owner/security/totp/setup` with the current owner password.
   The response contains a one-time pending secret and an `otpauthUri` suitable
   for a standard authenticator app. Do not log or share this response.
4. Add the account to the authenticator app and call
   `POST /v1/owner/security/totp/setup/confirm` with its current six-digit code.
5. Store the ten returned recovery codes offline in a password manager or
   another protected location. They are shown once; the server stores only
   SHA-256 digests and atomically consumes each code on use.

The owner login endpoint accepts the authenticator code or one unused recovery
code in the `totpCode` field. It does not issue a bearer session until the
second factor succeeds. Missing second factor returns HTTP 401 with
`detail.code = two_factor_required`. Invalid/replayed factors are rejected
and count toward the existing account/IP login throttle.

Enabling 2FA revokes every pre-existing owner session; sign in again with the
new second factor after saving the recovery codes. To disable 2FA, call
`DELETE /v1/owner/security/totp` with the current password and either a fresh
authenticator code or one unused recovery code. The operation removes recovery
material and revokes all owner sessions. If both the authenticator and all
recovery codes are lost, use the organization's offline operator recovery
process rather than bypassing the second factor.

## Optional security alert delivery

The backend writes authentication and security events to the audit trail and can
also deliver minimal alerts to an external HTTPS webhook. Configure both
`MEDIA_SECURITY_ALERT_WEBHOOK_URL` and `MEDIA_SECURITY_ALERT_WEBHOOK_TOKEN`
in the backend deployment secret manager. The URL must use HTTPS; redirects are
not followed. Delivery runs asynchronously and never blocks login. Events are
limited to new sessions, previously unseen client-network fingerprints, and
login throttling. Payloads contain an opaque user ID, role, event type and
timestamp; raw IP addresses, usernames, passwords, bearer tokens, TOTP seeds
and recovery codes are never sent.

Without both deployment variables, webhook delivery is intentionally disabled.
Email, push and SMS require a provider-specific adapter; the generic webhook
does not claim to send those message types.

## Session management

Authenticated users can inspect their own active sessions through
`GET /v1/auth/sessions` and revoke a selected session through
`DELETE /v1/auth/sessions/{sessionId}`. The returned session identifier is a
SHA-256 token digest used only as a revocation handle; it is not a bearer
credential. A user cannot inspect or revoke another account's sessions.
Logging out, password changes, role changes, account suspension, and 2FA
enrollment/disablement revoke the applicable sessions. Owner sessions expire
after 12 hours; standard account sessions expire after 30 days.

## Role permissions

API handlers enforce permissions server-side using the authenticated session
role and the persistent allow/deny override table. Unknown roles and unknown
permissions fail closed. Owner permission overrides remain owner-only.
Administrators cannot create another administrator or disable another
administrator. Support can reset only user/collaborator accounts. The owner
account cannot be changed, demoted, disabled, or reset through managed-account
routes.

Default grants are defined in `backend/authorization.py`. An explicit deny
override takes precedence over a role default. Review the effective permission
set and override list before granting sensitive access.

## Audit and operational controls

Successful login/logout, failed login, password changes, role/account changes,
permission overrides, Premium grants, and TOTP enrollment/disablement are
recorded in the account audit table. Audit details must never contain passwords,
tokens, TOTP seeds, recovery codes, cookies, or session credentials.

Login throttling is persisted in SQLite and keyed by hashed account/IP
identifiers. Account sessions are opaque random bearer values; only SHA-256
digests are stored, with server-side expiry and revocation. Serve all
authentication and media endpoints over HTTPS and protect database and backup
files with restrictive filesystem permissions.

## Deployment checklist

- [ ] Inject `MEDIA_TOTP_ENCRYPTION_KEY` through the backend secret manager.
- [ ] Configure `MEDIA_API_URL` for the app's target environment; use HTTPS in production.
- [ ] If external alerts are required, inject both webhook variables through the backend secret manager and test delivery.
- [ ] Back up the key separately from the encrypted account database.
- [ ] Verify HTTPS termination and ensure reverse-proxy client IP handling is trusted.
- [ ] Enroll the owner and securely save the one-time recovery codes.
- [ ] Verify password-only owner login is rejected after enrollment.
- [ ] Verify a TOTP replay and a used recovery code are rejected.
- [ ] Review owner/admin/support effective permissions and audit events.
- [ ] Never enable local insecure mode on a public or production deployment.

## Known operational integration boundary

The backend persists security audit events, but delivery of email, push, or SMS
alerts for suspicious logins requires a configured notification provider and
deployment credentials. No notification is claimed to have been sent by this
repository alone. Production notification delivery must be integrated and
tested before treating alerts as an active control.


## Backup retention

The Owner-only endpoint `POST /v1/owner/backups/retention` supports a preview-first cleanup policy.
It defaults to `dry_run=true`, retains at least the newest three valid backup files,
and considers only regular, non-symlink `.mibak` files with valid generated identifiers.
The retention period defaults to 90 days and is bounded to 1–3650 days; the minimum
retained count is bounded to 1–100. No files are removed during preview. Actual
deletion requires an authenticated Owner to explicitly set `dry_run=false`.
The API reports eligible and deleted identifiers for auditability. This is local
backup retention only; it does not implement remote replication, media-asset
backup, or disaster-recovery restore.



## Isolated restore preparation

The Owner-only endpoint `POST /v1/owner/backups/{backup_id}/restore/prepare`
decrypts a backup, validates its archive structure and SQLite integrity, then writes
a private staged database under `restore-staging`. It never overwrites or opens the
live account database for writing. The response exposes a generated stage identifier,
integrity result and table inventory, not a filesystem path. This is a preparation
step only: activation, maintenance-mode coordination, rollback, staged-file expiry,
and media-asset restore are not implemented and must not be implied by a successful
preparation response.

