import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen


data_dir = Path(os.environ.get("DATA_DIR", "/data"))
latest_path = data_dir / "latest.json"
max_age = float(os.environ.get("HEALTH_MAX_AGE_SECONDS", "60"))

try:
    payload = json.loads(latest_path.read_text())
    timestamp = payload["timestamp"].replace("Z", "+00:00")
    sample_time = datetime.fromisoformat(timestamp)
    age = time.time() - sample_time.timestamp()
except Exception as exc:
    print(f"healthcheck failed: {exc}", file=sys.stderr)
    raise SystemExit(1)

if age > max_age:
    print(f"latest sample is stale: {age:.1f}s", file=sys.stderr)
    raise SystemExit(1)

if os.environ.get("HEALTH_CHECK_WEB", "true").lower() in {"1", "true", "yes", "on"}:
    web_port = int(os.environ.get("WEB_PORT", "8090"))
    if web_port > 0:
        try:
            with urlopen(f"http://127.0.0.1:{web_port}/api/state", timeout=2) as response:
                if response.status != 200:
                    raise RuntimeError(f"unexpected status {response.status}")
        except Exception as exc:
            print(f"web healthcheck failed: {exc}", file=sys.stderr)
            raise SystemExit(1)

raise SystemExit(0)
