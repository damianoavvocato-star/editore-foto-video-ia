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
