"""Backend test defaults: explicitly opt into unauthenticated local test clients."""
import os

# TestClient runs in-process and is not exposed to a network. Production defaults
# remain fail-closed; tests opt into the local-only mode explicitly.
os.environ.setdefault('MEDIA_ALLOW_INSECURE_LOCAL', 'true')
