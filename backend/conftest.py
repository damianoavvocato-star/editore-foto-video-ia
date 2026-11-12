"""Backend test defaults: explicitly opt into unauthenticated local test clients."""
import os

# TestClient runs in-process and is not exposed to a network. Production defaults
# remain fail-closed; tests opt into the local-only mode explicitly.
os.environ.setdefault('MEDIA_ALLOW_INSECURE_LOCAL', 'true')

# Starlette's default TestClient peer name is "testclient", not an IP address.
# Give ordinary in-process test clients a loopback peer while allowing tests to
# explicitly pass a non-loopback address when exercising the network guard.
from starlette.testclient import TestClient

_original_test_client_init = TestClient.__init__


def _loopback_test_client_init(self, app, *args, **kwargs):
    kwargs.setdefault('client', ('127.0.0.1', 50000))
    _original_test_client_init(self, app, *args, **kwargs)


TestClient.__init__ = _loopback_test_client_init
