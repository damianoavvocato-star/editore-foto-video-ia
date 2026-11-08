import pytest
"""API safety regression tests: upload extension validation and health endpoint."""
import io
from fastapi.testclient import TestClient
from backend import server


def test_health_reports_backend_without_claiming_ai():
    client = TestClient(server.app)
    response = client.get('/health')
    assert response.status_code == 200
    assert response.json()['ok'] is True
    assert response.json()['aiProvider'] is False


def test_upload_rejects_unapproved_extension():
    client = TestClient(server.app)
    response = client.post('/v1/assets', files={'file': ('payload.exe', io.BytesIO(b'not media'), 'application/octet-stream')})
    assert response.status_code == 415


def test_upload_accepts_png_and_returns_generated_id(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'ASSETS', tmp_path)
    client = TestClient(server.app)
    response = client.post('/v1/assets', files={'file': ('image.png', io.BytesIO(b'png-test'), 'image/png')})
    assert response.status_code == 200
    data = response.json()
    assert len(data['assetId']) == 32
    saved = list(tmp_path.glob(data['assetId'] + '.png'))
    assert len(saved) == 1 and saved[0].read_bytes() == b'png-test'


def test_cancel_marks_running_job_and_sets_signal():
    from fastapi.testclient import TestClient
    job_id = 'd' * 32
    server.jobs[job_id] = {'state': 'rendering', 'progress': 0.2, 'message': 'Rendering'}
    server.cancel_events[job_id] = __import__('threading').Event()
    response = TestClient(server.app).delete('/v1/jobs/' + job_id)
    assert response.status_code == 200
    assert server.cancel_events[job_id].is_set()
    assert server.jobs[job_id]['state'] == 'cancelled'


def test_upload_rejects_empty_file(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'ASSETS', tmp_path)
    response = TestClient(server.app).post('/v1/assets', files={'file': ('empty.png', io.BytesIO(b''), 'image/png')})
    assert response.status_code == 400
    assert list(tmp_path.iterdir()) == []


def test_job_endpoints_reject_path_like_ids():
    client = TestClient(server.app)
    assert client.get('/v1/jobs/../../etc/passwd').status_code in (400, 404)
    assert client.delete('/v1/jobs/not-a-uuid').status_code == 400
    assert client.get('/v1/outputs/../../etc/passwd').status_code in (400, 404)


def test_output_is_not_available_before_job_completion(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'OUTPUTS', tmp_path)
    job_id = 'a' * 32
    server.jobs[job_id] = {'state': 'rendering', 'progress': 0.4, 'message': 'Rendering'}
    (tmp_path / f'{job_id}.mp4').write_bytes(b'partial')
    response = TestClient(server.app).get('/v1/outputs/' + job_id)
    assert response.status_code == 409


def test_completed_job_output_can_be_downloaded(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'OUTPUTS', tmp_path)
    job_id = 'b' * 32
    server.jobs[job_id] = {'state': 'completed', 'progress': 1.0, 'message': 'Done'}
    target = tmp_path / f'{job_id}.mp4'
    target.write_bytes(b'valid-output')
    response = TestClient(server.app).get('/v1/outputs/' + job_id)
    assert response.status_code == 200
    assert response.content == b'valid-output'


def test_cancelling_completed_job_does_not_change_terminal_state():
    job_id = 'c' * 32
    server.jobs[job_id] = {'state': 'completed', 'progress': 1.0, 'message': 'Done'}
    response = TestClient(server.app).delete('/v1/jobs/' + job_id)
    assert response.status_code == 200
    assert server.jobs[job_id]['state'] == 'completed'


def test_legacy_shared_token_is_not_accepted_as_account_identity(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', 'test-secret-token')
    monkeypatch.setattr(server, 'ALLOW_INSECURE_LOCAL', False)
    client = TestClient(server.app)
    assert client.get('/v1/jobs/' + 'e' * 32).status_code == 401
    assert client.get(
        '/v1/jobs/' + 'e' * 32, headers={'Authorization': 'Bearer test-secret-token'}
    ).status_code == 401


def test_legacy_shared_token_cannot_access_user_jobs(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', 'test-secret-token')
    monkeypatch.setattr(server, 'ALLOW_INSECURE_LOCAL', False)
    client = TestClient(server.app)
    response = client.get('/v1/jobs/' + 'f' * 32, headers={'Authorization': 'Bearer test-secret-token'})
    assert response.status_code == 401


def test_render_rejects_too_many_tracks():
    client = TestClient(server.app)
    response = client.post('/v1/render/jobs', json={'project': {'tracks': [{}] * 65}})
    assert response.status_code == 422


def test_render_rejects_too_many_clips():
    client = TestClient(server.app)
    clips = [{'kind': 'video'}] * 501
    response = client.post('/v1/render/jobs', json={'project': {'tracks': [{'clips': clips}]}})
    assert response.status_code == 422


def test_render_rejects_malformed_track():
    client = TestClient(server.app)
    response = client.post('/v1/render/jobs', json={'project': {'tracks': ['not-a-track']}})
    assert response.status_code == 422


def test_missing_server_token_fails_closed_outside_local_development(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', '')
    monkeypatch.setattr(server, 'ALLOW_INSECURE_LOCAL', False)
    client = TestClient(server.app)
    assert client.get('/health').status_code == 200
    response = client.get('/v1/jobs/' + '1' * 32)
    assert response.status_code == 401
    assert response.json()['detail'] == 'Sessione account obbligatoria.'


def test_insecure_mode_requires_explicit_local_opt_in(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', '')
    monkeypatch.setattr(server, 'ALLOW_INSECURE_LOCAL', True)
    local_client = TestClient(server.app, client=('127.0.0.1', 12345))
    response = local_client.get('/v1/jobs/' + '2' * 32)
    assert response.status_code == 404


def test_insecure_mode_rejects_non_loopback_clients(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', '')
    monkeypatch.setattr(server, 'ALLOW_INSECURE_LOCAL', True)
    remote_client = TestClient(server.app, client=('203.0.113.10', 12345))
    response = remote_client.get('/v1/jobs/' + '2' * 32)
    assert response.status_code == 403
    assert response.json()['detail'] == 'Unauthenticated access is restricted to local connections'



def test_render_failure_does_not_expose_server_traceback(tmp_path, monkeypatch):
    job_id = '9' * 32
    monkeypatch.setattr(server, 'ROOT', tmp_path)
    monkeypatch.setattr(server.shutil, 'which', lambda _binary: None)
    server.jobs[job_id] = {'state': 'queued', 'progress': 0.0, 'message': 'Queued'}
    server.cancel_events[job_id] = __import__('threading').Event()

    try:
        server._render_job(job_id, {'tracks': []}, {})
        status = TestClient(server.app).get('/v1/jobs/' + job_id)
        assert status.status_code == 200
        payload = status.json()
        assert payload['state'] == 'failed'
        assert payload['error'] == (
            'Errore interno durante il rendering. Consultare i log del server.'
        )
        assert 'Traceback' not in str(payload)
        assert str(tmp_path) not in str(payload)
    finally:
        server.jobs.pop(job_id, None)
        server.cancel_events.pop(job_id, None)


def test_owner_totp_api_requires_second_factor_before_session(tmp_path, monkeypatch):
    import time
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)
    from cryptography.fernet import Fernet
    from backend.accounts import AccountStore
    from backend.totp import code_at

    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("api_owner", "owner password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)
    token, _ = store.issue_session(owner["userId"])
    headers = {"Authorization": f"Bearer {token}"}

    status = client.get("/v1/owner/security/totp", headers=headers)
    assert status.status_code == 200 and status.json()["enabled"] is False

    setup = client.post(
        "/v1/owner/security/totp/setup",
        headers=headers,
        json={"password": "owner password long enough"},
    )
    assert setup.status_code == 200
    secret = setup.json()["secret"]
    assert setup.json()["otpauthUri"].startswith("otpauth://totp/")

    confirm = client.post(
        "/v1/owner/security/totp/setup/confirm",
        headers=headers,
        json={"code": code_at(secret, int(time.time()))},
    )
    assert confirm.status_code == 200
    recovery = confirm.json()["recoveryCodes"]
    assert len(recovery) == 10

    missing = client.post(
        "/v1/auth/login",
        json={"username": "api_owner", "password": "owner password long enough"},
    )
    assert missing.status_code == 401
    assert missing.json()["detail"]["code"] == "two_factor_required"
    assert "accessToken" not in missing.json()

    login = client.post(
        "/v1/auth/login",
        json={
            "username": "api_owner",
            "password": "owner password long enough",
            "totpCode": code_at(secret, int(time.time()) + 30),
        },
    )
    assert login.status_code == 200
    assert login.json()["accessToken"]
    assert client.get(
        "/v1/owner/security/totp", headers={
            "Authorization": "Bearer " + login.json()["accessToken"]
        }
    ).json()["enabled"] is True


def test_non_owner_cannot_manage_owner_totp(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("api_owner", "owner password long enough")
    admin = store.create_managed_account(
        owner["userId"], "api_admin", "admin password long enough", "admin"
    )
    store.change_password(admin["userId"], None, "admin changed password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    token, _ = store.issue_session(admin["userId"])
    response = TestClient(server.app).get(
        "/v1/owner/security/totp",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403


def test_owner_totp_login_fails_closed_when_encryption_key_is_missing(tmp_path, monkeypatch):
    import time
    clock = 1_700_000_000
    monkeypatch.setattr(time, "time", lambda: clock)
    from cryptography.fernet import Fernet
    from backend.accounts import AccountStore
    from backend.totp import code_at

    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("api_owner", "owner password long enough")
    secret = store.begin_totp_setup(owner["userId"], "owner password long enough")
    store.confirm_totp_setup(owner["userId"], code_at(secret, int(time.time())))
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.delenv("MEDIA_TOTP_ENCRYPTION_KEY")
    response = TestClient(server.app).post(
        "/v1/auth/login",
        json={
            "username": "api_owner",
            "password": "owner password long enough",
            "totpCode": code_at(secret, int(time.time()) + 30),
        },
    )
    assert response.status_code == 503
    assert "accessToken" not in response.json()


def test_account_management_routes_apply_role_permissions(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("perm_owner", "owner password long enough")
    admin = store.create_managed_account(
        owner["userId"], "perm_admin", "admin password long enough", "admin"
    )
    support = store.create_managed_account(
        owner["userId"], "perm_support", "support password long enough", "support"
    )
    store.change_password(admin["userId"], None, "admin changed password long enough")
    store.change_password(support["userId"], None, "support changed password long enough")
    regular = store.register("perm_user", "regular password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)

    def headers(user_id):
        token, _ = store.issue_session(user_id)
        return {"Authorization": f"Bearer {token}"}

    assert client.get("/v1/owner/accounts", headers=headers(admin["userId"])).status_code == 200
    assert client.get("/v1/owner/accounts", headers=headers(support["userId"])).status_code == 200
    assert client.get("/v1/owner/accounts", headers=headers(regular["userId"])).status_code == 403

    created = client.post(
        "/v1/owner/accounts",
        headers=headers(admin["userId"]),
        json={
            "username": "created_user",
            "temporaryPassword": "temporary password long",
            "role": "user",
        },
    )
    assert created.status_code == 200
    elevated = client.post(
        "/v1/owner/accounts",
        headers=headers(admin["userId"]),
        json={
            "username": "created_admin",
            "temporaryPassword": "temporary password long",
            "role": "admin",
        },
    )
    assert elevated.status_code == 403

    reset = client.post(
        f"/v1/owner/accounts/{regular['userId']}/reset-password",
        headers=headers(support["userId"]),
    )
    assert reset.status_code == 200
    assert reset.json()["temporaryPassword"]

    # A support account cannot reset an administrator's password.
    admin_reset = client.post(
        f"/v1/owner/accounts/{admin['userId']}/reset-password",
        headers=headers(support["userId"]),
    )
    assert admin_reset.status_code == 403

    assert client.get("/v1/owner/audit", headers=headers(admin["userId"])).status_code == 403
    assert client.get(
        "/v1/owner/security/totp", headers=headers(admin["userId"])
    ).status_code == 403


def test_owner_permission_override_is_enforced_by_api(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("perm_owner", "owner password long enough")
    admin = store.create_managed_account(
        owner["userId"], "perm_admin", "admin password long enough", "admin"
    )
    store.change_password(admin["userId"], None, "admin changed password long enough")
    target = store.register("premium_target", "target password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)

    owner_token, _ = store.issue_session(owner["userId"])
    admin_token, _ = store.issue_session(admin["userId"])
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    denied = client.get(
        f"/v1/owner/accounts/{target['userId']}/premium-grants",
        headers=admin_headers,
    )
    assert denied.status_code == 200  # billing.read is a default admin permission

    override = client.put(
        f"/v1/owner/accounts/{admin['userId']}/permissions",
        headers=owner_headers,
        json={"permission": "billing.grant", "effect": "deny"},
    )
    assert override.status_code == 200
    denied_after_override = client.post(
        f"/v1/owner/accounts/{target['userId']}/premium-grants",
        headers=admin_headers,
        json={"plan": "premium", "reason": "test"},
    )
    assert denied_after_override.status_code == 403


def test_owner_totp_setup_password_attempts_are_rate_limited(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from backend.accounts import AccountStore

    monkeypatch.setenv("MEDIA_TOTP_ENCRYPTION_KEY", Fernet.generate_key().decode("ascii"))
    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("rate_owner", "owner password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    token, _ = store.issue_session(owner["userId"])
    headers = {"Authorization": f"Bearer {token}"}
    client = TestClient(server.app)

    for _ in range(10):
        response = client.post(
            "/v1/owner/security/totp/setup",
            headers=headers,
            json={"password": "incorrect owner password"},
        )
        assert response.status_code == 422
    blocked = client.post(
        "/v1/owner/security/totp/setup",
        headers=headers,
        json={"password": "owner password long enough"},
    )
    assert blocked.status_code == 429


def test_collaborator_billing_read_is_limited_to_self(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("billing_owner", "owner password long enough")
    collaborator = store.create_managed_account(
        owner["userId"], "billing_collab", "collab password long enough", "collaborator"
    )
    store.change_password(
        collaborator["userId"], None, "collab changed password long enough"
    )
    other = store.register("billing_other", "other account password long")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    token, _ = store.issue_session(collaborator["userId"])
    headers = {"Authorization": f"Bearer {token}"}
    client = TestClient(server.app)

    own = client.get(
        f"/v1/owner/accounts/{collaborator['userId']}/premium-grants",
        headers=headers,
    )
    other_account = client.get(
        f"/v1/owner/accounts/{other['userId']}/premium-grants",
        headers=headers,
    )
    assert own.status_code == 200
    assert other_account.status_code == 403


def test_authenticated_session_inventory_and_revocation_api(tmp_path, monkeypatch):
    from backend.accounts import AccountStore
    import hashlib

    store = AccountStore(tmp_path / "accounts.sqlite3")
    first = store.register("session_user", "session user password long")
    other = store.register("session_other", "session other password long")
    _, first_token, _ = store.login("session_user", "session user password long")
    _, second_token, _ = store.login("session_user", "session user password long")
    _, other_token, _ = store.login("session_other", "session other password long")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)

    first_headers = {"Authorization": f"Bearer {first_token}"}
    other_headers = {"Authorization": f"Bearer {other_token}"}
    inventory = client.get("/v1/auth/sessions", headers=first_headers)
    assert inventory.status_code == 200
    sessions = inventory.json()["sessions"]
    current = next(item for item in sessions if item["current"])
    assert current["sessionId"] == hashlib.sha256(first_token.encode()).hexdigest()
    other_session_id = hashlib.sha256(second_token.encode()).hexdigest()

    forbidden = client.delete(
        f"/v1/auth/sessions/{other_session_id}",
        headers=other_headers,
    )
    assert forbidden.status_code == 404

    revoked = client.delete(
        f"/v1/auth/sessions/{other_session_id}",
        headers=first_headers,
    )
    assert revoked.status_code == 200
    assert revoked.json()["currentSessionRevoked"] is False
    assert store.resolve_session(second_token) is None
    assert store.resolve_session(first_token) is not None
    assert store.resolve_session(other_token) is not None

def test_interrupted_upload_removes_partial_file(tmp_path, monkeypatch):
    import asyncio
    from types import SimpleNamespace

    monkeypatch.setattr(server, 'ASSETS', tmp_path)

    class InterruptedUpload:
        filename = 'interrupted.png'
        calls = 0

        async def read(self, _size):
            self.calls += 1
            if self.calls == 1:
                return b'partial-bytes'
            raise OSError('simulated client disconnect')

        async def close(self):
            return None

    request = SimpleNamespace(
        state=SimpleNamespace(account=None, local_dev=True)
    )
    with pytest.raises(OSError, match='simulated client disconnect'):
        asyncio.run(server.upload_asset(request, InterruptedUpload()))

    assert list(tmp_path.iterdir()) == []




def test_render_api_retries_same_idempotent_request_after_restart(tmp_path, monkeypatch):
    from backend.job_store import JobRegistry

    monkeypatch.setattr(server, "ALLOW_INSECURE_LOCAL", True)
    monkeypatch.setattr(server, "ROOT", tmp_path)
    monkeypatch.setattr(server, "_render_job", lambda *_args: None)
    monkeypatch.setattr(server, "cancel_events", {})
    database = tmp_path / "jobs.sqlite3"
    first_registry = JobRegistry(database)
    monkeypatch.setattr(server, "jobs", first_registry)
    client = TestClient(server.app)
    headers = {"Idempotency-Key": "restart-render-key"}
    body = {"project": {"tracks": []}, "settings": {"resolution": "p720"}}

    first = client.post("/v1/render/jobs", json=body, headers=headers)
    assert first.status_code == 200
    first_job_id = first.json()["jobId"]
    assert first_registry[first_job_id]["state"] == "queued"

    # Recreate the registry to model a server restart: the old worker is gone.
    restored_registry = JobRegistry(database)
    monkeypatch.setattr(server, "jobs", restored_registry)
    assert restored_registry[first_job_id]["error"] == "worker_interrupted"

    changed = client.post(
        "/v1/render/jobs",
        json={"project": {"tracks": []}, "settings": {"resolution": "p1080"}},
        headers=headers,
    )
    assert changed.status_code == 409

    retry = client.post("/v1/render/jobs", json=body, headers=headers)
    assert retry.status_code == 200
    retry_job_id = retry.json()["jobId"]
    assert retry_job_id != first_job_id
    assert restored_registry[first_job_id]["state"] == "failed"
    assert restored_registry[retry_job_id]["state"] == "queued"



def test_magic_worker_start_failure_releases_job_claim_and_monthly_quota(tmp_path, monkeypatch):
    from backend.accounts import AccountStore
    from backend.usage_store import UsageStore
    from types import SimpleNamespace

    store = AccountStore(tmp_path / "accounts.sqlite3")
    user = store.register("magic_owner", "magic owner password long")
    token, _ = store.issue_session(user["userId"])
    asset_id = "a" * 32
    assets = tmp_path / "assets"
    assets.mkdir()
    (assets / f"{asset_id}.jpg").write_bytes(b"test-image")
    store.claim_media_resource("asset", asset_id, user["userId"])
    usage = UsageStore(tmp_path / "usage.sqlite3")

    monkeypatch.setattr(server, "ASSETS", assets)
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setattr(server, "_usage_store", lambda: usage)
    monkeypatch.setattr(server, "_entitlement_store", lambda: SimpleNamespace(
        has_premium=lambda _user_id: False
    ))
    monkeypatch.setattr(server, "_ai_monthly_limit", lambda _premium: 3)
    monkeypatch.setattr(server, "provider_configured", lambda: True)
    monkeypatch.setattr(server, "jobs", {})
    monkeypatch.setattr(server, "cancel_events", {})

    class FailingThread:
        def __init__(self, *args, **kwargs):
            pass

        def start(self):
            raise RuntimeError("simulated thread startup failure")

    client = TestClient(server.app)
    with client:
        # Start the TestClient portal before replacing Thread, so only the
        # endpoint's worker launch is simulated as unavailable.
        monkeypatch.setattr(server.threading, "Thread", FailingThread)
        response = client.post(
            "/v1/ai/jobs",
            headers={"Authorization": f"Bearer {token}"},
            json={"task": "magicIAedit", "assetIds": [asset_id]},
        )

    assert response.status_code == 503
    with store._connect() as db:
        job_claims = db.execute(
            "SELECT COUNT(*) FROM media_ownership WHERE resource_type='job' AND owner_user_id=?",
            (user["userId"],),
        ).fetchone()[0]
    import sqlite3
    with sqlite3.connect(usage.database) as db:
        reservations = db.execute(
            "SELECT COUNT(*) FROM ai_usage_reservations WHERE user_id=?",
            (user["userId"],),
        ).fetchone()[0]
    assert job_claims == 0
    assert reservations == 0
    assert server.jobs == {}
    assert server.cancel_events == {}



def test_render_worker_start_failure_releases_claim_and_allows_idempotent_retry(tmp_path, monkeypatch):
    import json
    import sqlite3
    from backend.accounts import AccountStore
    from backend.job_store import JobRegistry

    store = AccountStore(tmp_path / "accounts.sqlite3")
    user = store.register("render_owner", "render owner password long")
    token, _ = store.issue_session(user["userId"])
    asset_id = "c" * 32
    store.claim_media_resource("asset", asset_id, user["userId"])
    registry = JobRegistry(tmp_path / "jobs.sqlite3")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    monkeypatch.setattr(server, "jobs", registry)
    monkeypatch.setattr(server, "cancel_events", {})

    class FailingThread:
        def __init__(self, *args, **kwargs):
            pass

        def start(self):
            raise RuntimeError("simulated render worker startup failure")

    body = {
        "project": {"tracks": [{"kind": "video", "clips": [
            {"kind": "image", "assetId": asset_id, "durationMs": 1000}
        ]}]},
        "settings": {"resolution": "p720"},
    }
    client = TestClient(server.app)
    with client:
        monkeypatch.setattr(server.threading, "Thread", FailingThread)
        first = client.post(
            "/v1/render/jobs", json=body,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": "render-start-failure"},
        )
        second = client.post(
            "/v1/render/jobs", json=body,
            headers={"Authorization": f"Bearer {token}", "Idempotency-Key": "render-start-failure"},
        )

    assert first.status_code == 503
    assert second.status_code == 503
    with sqlite3.connect(registry.database) as db:
        rows = db.execute("SELECT job_id, payload FROM media_jobs ORDER BY updated_at").fetchall()
        mapping = db.execute(
            "SELECT job_id FROM render_idempotency WHERE idempotency_key=?",
            ("render-start-failure",),
        ).fetchone()
    assert len(rows) == 2
    failed_ids = [job_id for job_id, _ in rows]
    assert len(set(failed_ids)) == 2
    assert all(json.loads(payload)["error"] == "worker_start_failed" for _, payload in rows)
    assert mapping[0] == failed_ids[-1]
    assert registry[failed_ids[0]]["state"] == "failed"
    assert registry[failed_ids[1]]["state"] == "failed"
    assert server.cancel_events == {}
    with store._connect() as db:
        job_claims = db.execute(
            "SELECT COUNT(*) FROM media_ownership WHERE resource_type='job' AND owner_user_id=?",
            (user["userId"],),
        ).fetchone()[0]
    assert job_claims == 0
    assert store.owns_media_resource("asset", asset_id, user["userId"]) is True



def test_upload_accepts_pdf_document(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'ASSETS', tmp_path)
    response = TestClient(server.app).post(
        '/v1/assets',
        files={'file': ('brief.pdf', io.BytesIO(b'%PDF-1.7\\nexample'), 'application/pdf')},
    )
    assert response.status_code == 200
    asset_id = response.json()['assetId']
    assert (tmp_path / f'{asset_id}.pdf').read_bytes().startswith(b'%PDF-')


def test_upload_rejects_fake_pdf_extension(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'ASSETS', tmp_path)
    response = TestClient(server.app).post(
        '/v1/assets',
        files={'file': ('fake.pdf', io.BytesIO(b'not a pdf'), 'application/pdf')},
    )
    assert response.status_code == 415
    assert list(tmp_path.iterdir()) == []


def test_admin_dashboard_is_admin_only_and_returns_aggregates(tmp_path, monkeypatch):
    from backend.accounts import AccountStore

    store = AccountStore(tmp_path / "accounts.sqlite3")
    owner = store.bootstrap_owner("dashboard_owner", "owner password long enough")
    admin = store.create_managed_account(
        owner["userId"], "dashboard_admin", "admin password long enough", "admin"
    )
    support = store.create_managed_account(
        owner["userId"], "dashboard_support", "support password long enough", "support"
    )
    user = store.register("dashboard_user", "user password long enough")
    store.change_password(admin["userId"], None, "admin changed password long enough")
    store.change_password(support["userId"], None, "support changed password long enough")
    monkeypatch.setattr(server, "_account_store", lambda: store)
    client = TestClient(server.app)

    def headers(user_id):
        token, _ = store.issue_session(user_id)
        return {"Authorization": f"Bearer {token}"}

    response = client.get("/v1/admin/dashboard", headers=headers(admin["userId"]))
    assert response.status_code == 200
    dashboard = response.json()["dashboard"]
    assert dashboard["totalAccounts"] == 4
    assert dashboard["activeAccounts"] == 4
    assert dashboard["disabledAccounts"] == 0
    assert dashboard["accountsByRole"]["admin"] == 1
    assert dashboard["createdLast30Days"] == 4
    assert "username" not in dashboard

    assert client.get("/v1/admin/dashboard", headers=headers(owner["userId"])).status_code == 403
    assert client.get("/v1/admin/dashboard", headers=headers(support["userId"])).status_code == 403
    assert client.get("/v1/admin/dashboard", headers=headers(user["userId"])).status_code == 403
    assert client.get("/v1/admin/dashboard").status_code == 401
