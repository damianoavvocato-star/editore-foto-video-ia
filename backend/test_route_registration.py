"""Regression checks for FastAPI route registration."""

from backend import server


def test_http_method_and_path_pairs_are_registered_only_once():
    registered = []
    for route in server.app.routes:
        path = getattr(route, "path", None)
        methods = getattr(route, "methods", None) or set()
        if not path:
            continue
        registered.extend((method, path) for method in methods)

    assert len(registered) == len(set(registered)), (
        "Duplicate HTTP route registrations detected: "
        f"{[item for item in registered if registered.count(item) > 1]}"
    )
