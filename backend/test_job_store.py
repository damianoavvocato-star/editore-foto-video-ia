from backend.job_store import JobRegistry


def test_job_state_and_result_survive_registry_restart(tmp_path):
    database = tmp_path / "private" / "jobs.sqlite3"
    jobs = JobRegistry(database)
    jobs["a" * 32] = {
        "state": "queued",
        "progress": 0.0,
        "message": "In coda",
    }
    jobs["a" * 32].update(
        state="succeeded",
        progress=1.0,
        message="Proposta pronta",
        result={"clips": [{"assetId": "b" * 32}]},
    )

    restored = JobRegistry(database)
    assert restored["a" * 32]["state"] == "succeeded"
    assert restored["a" * 32]["result"]["clips"][0]["assetId"] == "b" * 32


def test_orphaned_active_jobs_are_marked_failed_after_restart(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    jobs = JobRegistry(database)
    jobs["c" * 32] = {
        "state": "rendering",
        "progress": 0.4,
        "message": "Rendering",
    }

    restored = JobRegistry(database)
    assert restored["c" * 32]["state"] == "failed"
    assert restored["c" * 32]["error"] == "worker_interrupted"
    assert "riavvio" in restored["c" * 32]["message"]


def test_terminal_job_state_is_not_changed_on_restart(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    jobs = JobRegistry(database)
    jobs["d" * 32] = {"state": "cancelled", "progress": 0.0}

    restored = JobRegistry(database)
    assert restored["d" * 32]["state"] == "cancelled"


def test_pop_removes_job_from_durable_registry(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    jobs = JobRegistry(database)
    jobs["e" * 32] = {"state": "failed"}
    jobs.pop("e" * 32)

    assert "e" * 32 not in JobRegistry(database)


def test_database_file_is_private_immediately_after_initialization(tmp_path):
    import os
    import stat

    if os.name != "posix":
        return

    database = tmp_path / "private" / "jobs.sqlite3"
    JobRegistry(database)

    assert stat.S_IMODE(database.stat().st_mode) == 0o600


def test_individual_field_mutations_are_persisted(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    jobs = JobRegistry(database)
    jobs["f" * 32] = {"state": "queued", "progress": 0.0}

    jobs["f" * 32]["progress"] = 0.5
    jobs["f" * 32]["message"] = "Elaborazione"
    # Queued jobs are intentionally marked interrupted on restart. Move this
    # record to a terminal state to isolate field-mutation persistence.
    jobs["f" * 32]["state"] = "succeeded"

    restored = JobRegistry(database)
    assert restored["f" * 32]["progress"] == 0.5
    assert restored["f" * 32]["message"] == "Elaborazione"

    del jobs["f" * 32]["message"]
    restored_after_delete = JobRegistry(database)
    assert "message" not in restored_after_delete["f" * 32]



def test_idempotency_reservation_is_shared_between_registry_instances(tmp_path):
    import threading
    import uuid

    database = tmp_path / "jobs.sqlite3"
    first_registry = JobRegistry(database)
    second_registry = JobRegistry(database)
    barrier = threading.Barrier(2)
    results = []

    def reserve(registry):
        barrier.wait()
        results.append(registry.create_idempotent_job(
            uuid.uuid4().hex,
            {"state": "queued", "progress": 0.0},
            "account-scope",
            "same-render-key",
            "same-fingerprint",
        ))

    workers = [
        threading.Thread(target=reserve, args=(first_registry,)),
        threading.Thread(target=reserve, args=(second_registry,)),
    ]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join(timeout=5)

    assert all(not worker.is_alive() for worker in workers)
    assert len(results) == 2
    assert results[0][0] == results[1][0]
    assert sorted(created for _, created in results) == [False, True]


def test_idempotency_reservation_rejects_changed_fingerprint(tmp_path):
    import uuid
    import pytest
    from backend.job_store import IdempotencyConflict

    registry = JobRegistry(tmp_path / "jobs.sqlite3")
    registry.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "same-render-key",
        "fingerprint-one",
    )

    with pytest.raises(IdempotencyConflict):
        registry.create_idempotent_job(
            uuid.uuid4().hex,
            {"state": "queued", "progress": 0.0},
            "account-scope",
            "same-render-key",
            "fingerprint-two",
        )


def test_idempotency_reservation_survives_registry_restart(tmp_path):
    import uuid

    database = tmp_path / "jobs.sqlite3"
    first = JobRegistry(database)
    job_id, created = first.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "succeeded", "progress": 1.0},
        "account-scope",
        "durable-render-key",
        "fingerprint",
    )
    restored = JobRegistry(database)

    replayed_id, replayed_created = restored.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "durable-render-key",
        "fingerprint",
    )

    assert created is True
    assert replayed_created is False
    assert replayed_id == job_id



def test_registry_get_refreshes_state_written_by_another_instance(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    writer = JobRegistry(database)
    reader = JobRegistry(database)
    job_id = "9" * 32
    writer[job_id] = {"state": "queued", "progress": 0.0}

    assert reader.get(job_id)["state"] == "queued"

    writer[job_id].update(state="completed", progress=1.0)
    assert reader.get(job_id)["state"] == "completed"
    assert reader.get(job_id)["progress"] == 1.0



def test_legacy_idempotency_metadata_is_migrated_on_registry_startup(tmp_path):
    import json
    import sqlite3
    import uuid

    database = tmp_path / "jobs.sqlite3"
    job_id = uuid.uuid4().hex
    legacy_values = {
        "state": "succeeded",
        "progress": 1.0,
        "_idempotency_scope": "account-scope",
        "_idempotency_key": "legacy-key",
        "_request_fingerprint": "legacy-fingerprint",
    }
    with sqlite3.connect(database) as connection:
        connection.execute(
            """CREATE TABLE media_jobs (
                job_id TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                updated_at REAL NOT NULL
            )"""
        )
        connection.execute(
            "INSERT INTO media_jobs(job_id,payload,updated_at) VALUES(?,?,?)",
            (job_id, json.dumps(legacy_values), 123.0),
        )

    restored = JobRegistry(database)
    replayed_id, created = restored.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "legacy-key",
        "legacy-fingerprint",
    )

    assert created is False
    assert replayed_id == job_id
