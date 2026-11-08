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
    monkeypatch.setattr(server, "_account_store", lambda: store)
    token, _ = store.issue_session(admin["userId"])
    response = TestClient(server.app).get(
        "/v1/owner/security/totp",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403


def test_owner_totp_login_fails_closed_when_encryption_key_is_missing(tmp_path, monkeypatch):
    import time
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
