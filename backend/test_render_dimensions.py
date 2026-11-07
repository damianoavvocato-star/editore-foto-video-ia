from backend.server import _render_dimensions


def test_render_dimensions_preserve_portrait_orientation():
    assert _render_dimensions({'width': 1080, 'height': 1920}, 'p1080') == (1080, 1920)
    assert _render_dimensions({'width': 720, 'height': 1280}, 'p720') == (720, 1280)


def test_render_dimensions_preserve_landscape_orientation():
    assert _render_dimensions({'width': 1920, 'height': 1080}, 'p1080') == (1920, 1080)
    assert _render_dimensions({'width': 3840, 'height': 2160}, 'p2160') == (3840, 2160)


def test_render_dimensions_use_safe_defaults_for_invalid_project_size():
    assert _render_dimensions({'width': 'invalid', 'height': None}, 'p1080') == (1080, 1920)


def test_render_dimensions_clamp_invalid_resolution_to_1080p():
    assert _render_dimensions({'width': 1920, 'height': 1080}, 'unknown') == (1920, 1080)
