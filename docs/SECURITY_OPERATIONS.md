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

Do not rotate this key by simply replacing the environment value: existing
TOTP seeds must first be decrypted with the old key and re-encrypted with the
new key in a controlled maintenance operation. A key rotation utility is not
part of this implementation.

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

To disable 2FA, call `DELETE /v1/owner/security/totp` with the current password
and a fresh authenticator code. The operation removes recovery material and
revokes all owner sessions. Recovery codes can be used at login, but not to
disable 2FA; if the authenticator is lost, use the organization's documented
operator recovery process rather than bypassing the second factor.

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
