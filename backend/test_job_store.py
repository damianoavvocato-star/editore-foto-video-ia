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



def test_interrupted_idempotent_job_can_be_retried_once_after_restart(tmp_path):
    import uuid

    database = tmp_path / "jobs.sqlite3"
    first = JobRegistry(database)
    old_job_id, created = first.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "rendering", "progress": 0.4},
        "account-scope",
        "retry-render-key",
        "same-fingerprint",
    )
    assert created is True

    restored = JobRegistry(database)
    assert restored[old_job_id]["error"] == "worker_interrupted"

    new_job_id, retried = restored.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "retry-render-key",
        "same-fingerprint",
    )
    assert retried is True
    assert new_job_id != old_job_id
    assert restored[old_job_id]["state"] == "failed"
    assert restored[new_job_id]["state"] == "queued"

    replayed_id, replayed_created = restored.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "retry-render-key",
        "same-fingerprint",
    )
    assert replayed_created is False
    assert replayed_id == new_job_id


def test_idempotent_job_retry_does_not_replace_regular_failure(tmp_path):
    import uuid

    database = tmp_path / "jobs.sqlite3"
    registry = JobRegistry(database)
    original_id, _ = registry.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "failed", "error": "ffmpeg_failed"},
        "account-scope",
        "stable-failure-key",
        "same-fingerprint",
    )

    replayed_id, created = registry.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "stable-failure-key",
        "same-fingerprint",
    )
    assert created is False
    assert replayed_id == original_id


def test_concurrent_retries_share_one_new_job_after_interruption(tmp_path):
    import threading
    import uuid

    database = tmp_path / "jobs.sqlite3"
    original = JobRegistry(database)
    original.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "rendering", "progress": 0.2},
        "account-scope",
        "concurrent-retry-key",
        "same-fingerprint",
    )
    first = JobRegistry(database)
    second = JobRegistry(database)
    barrier = threading.Barrier(2)
    results = []

    def retry(registry):
        barrier.wait()
        results.append(registry.create_idempotent_job(
            uuid.uuid4().hex,
            {"state": "queued", "progress": 0.0},
            "account-scope",
            "concurrent-retry-key",
            "same-fingerprint",
        ))

    workers = [
        threading.Thread(target=retry, args=(first,)),
        threading.Thread(target=retry, args=(second,)),
    ]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join(timeout=5)

    assert all(not worker.is_alive() for worker in workers)
    assert len(results) == 2
    assert results[0][0] == results[1][0]
    assert sorted(created for _, created in results) == [False, True]



def test_interrupted_job_retry_still_rejects_changed_fingerprint(tmp_path):
    import uuid
    import pytest
    from backend.job_store import IdempotencyConflict

    database = tmp_path / "jobs.sqlite3"
    first = JobRegistry(database)
    first.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "rendering", "progress": 0.3},
        "account-scope",
        "interrupted-changed-payload",
        "original-fingerprint",
    )

    restored = JobRegistry(database)
    with pytest.raises(IdempotencyConflict):
        restored.create_idempotent_job(
            uuid.uuid4().hex,
            {"state": "queued", "progress": 0.0},
            "account-scope",
            "interrupted-changed-payload",
            "different-fingerprint",
        )

    replayed_id, created = restored.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "interrupted-changed-payload",
        "original-fingerprint",
    )
    assert created is True
    assert restored[replayed_id]["state"] == "queued"



def test_idempotent_job_with_worker_start_failure_can_be_retried(tmp_path):
    import uuid

    database = tmp_path / "jobs.sqlite3"
    registry = JobRegistry(database)
    failed_id, created = registry.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "failed", "progress": 0.0, "error": "worker_start_failed"},
        "account-scope",
        "thread-start-retry-key",
        "same-fingerprint",
    )
    assert created is True

    retry_id, retried = registry.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "thread-start-retry-key",
        "same-fingerprint",
    )
    assert retried is True
    assert retry_id != failed_id
    assert registry[failed_id]["error"] == "worker_start_failed"
    assert registry[retry_id]["state"] == "queued"

    replay_id, replayed = registry.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "thread-start-retry-key",
        "same-fingerprint",
    )
    assert replayed is False
    assert replay_id == retry_id

def test_pop_removes_job_created_by_another_registry_instance(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    writer = JobRegistry(database)
    reader = JobRegistry(database)
    job_id = "1" * 32
    writer[job_id] = {"state": "succeeded", "result": {"assetId": "2" * 32}}

    removed = reader.pop(job_id)

    assert removed["state"] == "succeeded"
    assert removed["result"]["assetId"] == "2" * 32
    assert job_id not in reader
    assert job_id not in JobRegistry(database)


def test_pop_returns_default_for_missing_durable_job(tmp_path):
    jobs = JobRegistry(tmp_path / "jobs.sqlite3")

    assert jobs.pop("missing-job", None) is None


def test_pop_rejects_multiple_default_arguments(tmp_path):
    import pytest

    jobs = JobRegistry(tmp_path / "jobs.sqlite3")
    with pytest.raises(TypeError, match="at most 2 arguments"):
        jobs.pop("missing-job", None, None)

def test_get_evicts_stale_cache_after_another_registry_removes_job(tmp_path):
    database = tmp_path / "jobs.sqlite3"
    writer = JobRegistry(database)
    reader = JobRegistry(database)
    job_id = "3" * 32
    writer[job_id] = {"state": "succeeded", "result": {"value": "old"}}

    assert reader.get(job_id)["result"]["value"] == "old"
    writer.pop(job_id)

    assert reader.get(job_id) is None
    assert job_id not in reader


def test_clear_removes_jobs_and_idempotency_for_all_registry_instances(tmp_path):
    import uuid

    database = tmp_path / "jobs.sqlite3"
    writer = JobRegistry(database)
    reader = JobRegistry(database)
    job_id = uuid.uuid4().hex
    writer.create_idempotent_job(
        job_id,
        {"state": "succeeded", "progress": 1.0},
        "account-scope",
        "clear-key",
        "clear-fingerprint",
    )
    assert reader.get(job_id)["state"] == "succeeded"

    writer.clear()

    assert job_id not in JobRegistry(database)
    assert reader.get(job_id) is None
    assert job_id not in reader

    replacement_id, created = reader.create_idempotent_job(
        uuid.uuid4().hex,
        {"state": "queued", "progress": 0.0},
        "account-scope",
        "clear-key",
        "clear-fingerprint",
    )
    assert created is True
    assert replacement_id != job_id



def test_failed_job_update_restores_in_memory_snapshot(tmp_path, monkeypatch):
    import pytest

    database = tmp_path / "jobs.sqlite3"
    jobs = JobRegistry(database)
    job_id = "4" * 32
    jobs[job_id] = {"state": "succeeded", "message": "saved"}
    record = jobs[job_id]

    def fail_save(*args, **kwargs):
        raise OSError("disk unavailable")

    monkeypatch.setattr(jobs, "_save", fail_save)
    with pytest.raises(OSError, match="disk unavailable"):
        record.update(state="failed", message="not saved", extra=True)

    assert record == {"state": "succeeded", "message": "saved"}
    assert JobRegistry(database)[job_id] == {"state": "succeeded", "message": "saved"}


def test_failed_job_field_set_and_delete_restore_snapshot(tmp_path, monkeypatch):
    import pytest

    database = tmp_path / "jobs.sqlite3"
    jobs = JobRegistry(database)
    job_id = "5" * 32
    jobs[job_id] = {"state": "succeeded", "message": "saved"}
    record = jobs[job_id]

    def fail_save(*args, **kwargs):
        raise OSError("disk unavailable")

    monkeypatch.setattr(jobs, "_save", fail_save)
    with pytest.raises(OSError, match="disk unavailable"):
        record["message"] = "not saved"
    assert record["message"] == "saved"

    with pytest.raises(OSError, match="disk unavailable"):
        del record["message"]
    assert record["message"] == "saved"


def test_failed_registry_insert_does_not_publish_in_memory_job(tmp_path, monkeypatch):
    import pytest

    jobs = JobRegistry(tmp_path / "jobs.sqlite3")

    def fail_save(*args, **kwargs):
        raise OSError("disk unavailable")

    monkeypatch.setattr(jobs, "_save", fail_save)
    job_id = "6" * 32
    with pytest.raises(OSError, match="disk unavailable"):
        jobs[job_id] = {"state": "queued"}

    assert job_id not in jobs
    assert JobRegistry(jobs.database).get(job_id) is None
