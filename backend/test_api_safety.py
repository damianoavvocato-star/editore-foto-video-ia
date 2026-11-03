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


def test_configured_token_rejects_missing_and_incorrect_credentials(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', 'test-secret-token')
    client = TestClient(server.app)
    assert client.get('/v1/jobs/' + 'e' * 32).status_code == 401
    assert client.get(
        '/v1/jobs/' + 'e' * 32, headers={'Authorization': 'Bearer wrong-token'}
    ).status_code == 401


def test_configured_token_accepts_correct_credentials(monkeypatch):
    monkeypatch.setattr(server, 'TOKEN', 'test-secret-token')
    client = TestClient(server.app)
    response = client.get(
        '/v1/jobs/' + 'f' * 32,
        headers={'Authorization': 'Bearer test-secret-token'},
    )
    assert response.status_code == 404


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
