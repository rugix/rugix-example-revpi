"""Check that the DIO controller web API is serving fresh sample data."""

import json
import sys
import time
from datetime import datetime
from urllib.request import urlopen


MAX_SAMPLE_AGE_SECONDS = 60
WEB_PORT = 8090

try:
    with urlopen(f"http://127.0.0.1:{WEB_PORT}/api/state", timeout=2) as response:
        if response.status != 200:
            raise RuntimeError(f"unexpected status {response.status}")
        payload = json.loads(response.read().decode("utf-8"))
    timestamp = payload["timestamp"].replace("Z", "+00:00")
    sample_time = datetime.fromisoformat(timestamp)
    age = time.time() - sample_time.timestamp()
except Exception as exc:
    print(f"healthcheck failed: {exc}", file=sys.stderr)
    raise SystemExit(1)

if age > MAX_SAMPLE_AGE_SECONDS:
    print(f"latest sample is stale: {age:.1f}s", file=sys.stderr)
    raise SystemExit(1)
