import json
import logging
import math
import os
import signal
import sys
import threading
import time
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS


APP_NAME = "revpi-dio-grafana"
LOCAL_STATE_SCHEMA_VERSION = 2
STATIC_DIR = Path(__file__).with_name("static")


def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def parse_names(value):
    return [item.strip() for item in value.split(",") if item.strip()]


def parse_bool_value(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, int) and value in {0, 1}:
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
    raise ValueError("expected boolean value")


def utc_now():
    return datetime.now(timezone.utc)


def isoformat(dt):
    return dt.isoformat().replace("+00:00", "Z")


def atomic_write_json(path, payload):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def empty_state():
    return {
        "schemaVersion": LOCAL_STATE_SCHEMA_VERSION,
        "lastCounterValues": {},
        "lastCounterSeenAt": {},
    }


def resolve_config_rsc():
    candidates = [
        os.environ.get("REVPI_CONFIG_RSC", "/etc/revpi/config.rsc"),
        "/etc/revpi/config.rsc",
        "/opt/KUNBUS/config.rsc",
    ]
    seen = set()
    checked = []
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        path = Path(candidate)
        checked.append(str(path))
        if path.is_file():
            return str(path)
        if path.exists():
            logging.warning("PiCtory config candidate %s is not a file", path)

    raise RuntimeError(
        "can not read PiCtory config.rsc inside the container; checked "
        f"{', '.join(checked)}. Make sure PiCtory saved the start configuration "
        "and that docker-compose.yml bind-mounts the host config file through "
        "REVPI_CONFIG_RSC_HOST."
    )


def migrate_local_state(raw):
    if not raw:
        return empty_state()

    version = int(raw.get("schemaVersion", 0))
    if version == LOCAL_STATE_SCHEMA_VERSION:
        raw.setdefault("lastCounterValues", {})
        raw.setdefault("lastCounterSeenAt", {})
        return raw

    if version in {0, 1}:
        # v1 stored software edge counts. v2 derives rates from the DIO
        # counter values, so only the new counter-rate state is retained.
        return empty_state()

    if version > LOCAL_STATE_SCHEMA_VERSION:
        logging.warning(
            "local state schema version %s is newer than this controller supports",
            version,
        )
        raw.setdefault("lastCounterValues", {})
        raw.setdefault("lastCounterSeenAt", {})
        return raw

    raw["schemaVersion"] = LOCAL_STATE_SCHEMA_VERSION
    raw.setdefault("lastCounterValues", {})
    raw.setdefault("lastCounterSeenAt", {})
    return raw


def read_state_file(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except json.JSONDecodeError:
        backup = path.with_suffix(path.suffix + ".broken")
        try:
            path.replace(backup)
            logging.warning("moved unreadable state file to %s", backup)
        except OSError as exc:
            logging.warning("could not move unreadable state file %s: %s", path, exc)
        return None


def load_state(path, legacy_path=None):
    raw = read_state_file(path)
    if raw is None and legacy_path is not None and legacy_path.is_file():
        logging.info("loading legacy controller state from %s", legacy_path)
        raw = read_state_file(legacy_path)
    return migrate_local_state(raw)


class InfluxStore:
    def __init__(self, url, token, org, bucket):
        self.url = url
        self.token = token
        self.org = org
        self.bucket = bucket
        self.client = InfluxDBClient(url=url, token=token, org=org)
        self.write_api = self.client.write_api(write_options=SYNCHRONOUS)

    def wait_until_ready(self, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if self.client.ping():
                    return
            except Exception as exc:
                logging.info("waiting for InfluxDB: %s", exc)
            time.sleep(2)
        raise RuntimeError("InfluxDB did not become ready")

    def ensure_bucket(self):
        buckets = self.client.buckets_api()
        bucket = buckets.find_bucket_by_name(self.bucket)
        if bucket is None:
            logging.info("creating InfluxDB bucket %s", self.bucket)
            buckets.create_bucket(bucket_name=self.bucket, org=self.org)

    def current_schema_version(self):
        query = f'''
from(bucket: "{self.bucket}")
  |> range(start: -3650d)
  |> filter(fn: (r) => r._measurement == "revpi_app_schema")
  |> filter(fn: (r) => r.app == "{APP_NAME}" and r._field == "version")
  |> last()
'''
        try:
            tables = self.client.query_api().query(query=query, org=self.org)
        except Exception as exc:
            logging.info("schema marker query failed, treating as first install: %s", exc)
            return None

        for table in tables:
            for record in table.records:
                return str(record.get_value())
        return None

    def ensure_schema_marker(self, version):
        previous = self.current_schema_version()
        if previous != version:
            logging.info("recording app schema version %s (previous: %s)", version, previous)
        point = (
            Point("revpi_app_schema")
            .tag("app", APP_NAME)
            .field("version", version)
            .field("contract", "revpi_dio_counter_v1")
            .time(utc_now(), WritePrecision.NS)
        )
        self.write_api.write(bucket=self.bucket, org=self.org, record=point)

    def write(self, points):
        if points:
            self.write_api.write(bucket=self.bucket, org=self.org, record=points)


class RuntimeState:
    def __init__(self, input_names, counter_names, output_names):
        self.lock = threading.RLock()
        self.payload = {
            "app": APP_NAME,
            "timestamp": None,
            "inputs": {name: {"state": None} for name in input_names},
            "counters": {
                name: {"value": None, "delta": None, "pulsesPerMinute": None}
                for name in counter_names
            },
            "outputs": {name: {"state": None} for name in output_names},
            "schemaVersion": LOCAL_STATE_SCHEMA_VERSION,
        }

    def update(self, payload):
        with self.lock:
            self.payload = dict(payload)
            self.payload["app"] = APP_NAME

    def patch_output(self, name, state):
        with self.lock:
            outputs = self.payload.setdefault("outputs", {})
            outputs[name] = {"state": int(state)}
            self.payload["timestamp"] = isoformat(utc_now())

    def snapshot(self):
        with self.lock:
            return json.loads(json.dumps(self.payload))


def write_json(handler, status, payload):
    body = json.dumps(payload, sort_keys=True).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def read_json_body(handler):
    length = int(handler.headers.get("Content-Length", "0"))
    if length > 4096:
        raise ValueError("request body too large")
    if length == 0:
        return {}
    return json.loads(handler.rfile.read(length).decode("utf-8"))


def content_type_for(path):
    suffix = path.suffix.lower()
    if suffix == ".html":
        return "text/html; charset=utf-8"
    if suffix == ".css":
        return "text/css; charset=utf-8"
    if suffix == ".js":
        return "application/javascript; charset=utf-8"
    return "application/octet-stream"


def make_web_handler(runtime_state, reader):
    class AppHandler(BaseHTTPRequestHandler):
        server_version = "RevPiDIOWeb/0.1"

        def log_message(self, fmt, *args):
            logging.info("web %s - %s", self.address_string(), fmt % args)

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path == "/api/state":
                write_json(self, HTTPStatus.OK, runtime_state.snapshot())
                return
            if parsed.path in {"", "/"}:
                self.serve_static("index.html")
                return
            if parsed.path in {"/app.js", "/styles.css"}:
                self.serve_static(parsed.path.lstrip("/"))
                return
            write_json(self, HTTPStatus.NOT_FOUND, {"error": "not found"})

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path == "/api/outputs":
                self.set_output_from_body(None)
                return
            if parsed.path.startswith("/api/outputs/"):
                name = unquote(parsed.path.removeprefix("/api/outputs/")).strip()
                self.set_output_from_body(name)
                return
            write_json(self, HTTPStatus.NOT_FOUND, {"error": "not found"})

        def set_output_from_body(self, path_name):
            try:
                payload = read_json_body(self)
                name = path_name or str(payload.get("name", "")).strip()
                state = parse_bool_value(payload.get("state"))
                if not name:
                    raise ValueError("missing output name")
                actual = reader.set_output(name, state)
                runtime_state.patch_output(name, actual)
            except KeyError as exc:
                write_json(self, HTTPStatus.NOT_FOUND, {"error": str(exc)})
                return
            except ValueError as exc:
                write_json(self, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
                return
            except Exception as exc:
                logging.exception("failed to set output")
                write_json(
                    self,
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"error": f"failed to set output: {exc}"},
                )
                return

            write_json(
                self,
                HTTPStatus.OK,
                {"ok": True, "output": name, "state": int(actual)},
            )

        def serve_static(self, relative_path):
            parts = [part for part in relative_path.split("/") if part]
            if not parts or any(part in {".", ".."} for part in parts):
                write_json(self, HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            path = STATIC_DIR.joinpath(*parts)
            if not path.is_file():
                write_json(self, HTTPStatus.NOT_FOUND, {"error": "not found"})
                return

            body = path.read_bytes()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", content_type_for(path))
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(body)

    return AppHandler


def start_web_server(bind, port, runtime_state, reader):
    if port <= 0:
        logging.info("web UI disabled")
        return None
    server = ThreadingHTTPServer((bind, port), make_web_handler(runtime_state, reader))
    thread = threading.Thread(target=server.serve_forever, name="web-ui", daemon=True)
    thread.start()
    logging.info("serving DIO web UI on %s:%s", bind, port)
    return server


class SimulatedReader:
    def __init__(self, input_names, counter_names, output_names):
        self.input_names = input_names
        self.counter_names = counter_names
        self.output_names = output_names
        self.outputs = {name: False for name in output_names}
        self.lock = threading.RLock()
        self.start = time.monotonic()

    def read(self):
        now = time.monotonic() - self.start
        states = {}
        for index, name in enumerate(self.input_names):
            period = 2.0 + index
            states[name] = bool(math.floor(now / period) % 2)
        counters = {}
        for index, name in enumerate(self.counter_names):
            period = 0.75 + index * 0.4
            counters[name] = int(now / period)
        with self.lock:
            outputs = dict(self.outputs)
        return states, counters, outputs

    def set_output(self, name, state):
        with self.lock:
            if name not in self.outputs:
                raise KeyError(f"output {name} is not configured")
            self.outputs[name] = bool(state)
            return self.outputs[name]

    def reset_counters(self):
        return

    def close(self):
        return


class RevPiReader:
    def __init__(self, input_names, counter_names, output_names):
        import revpimodio2

        config_rsc = resolve_config_rsc()
        logging.info("using PiCtory config %s", config_rsc)
        self.lock = threading.RLock()
        modio_kwargs = {
            "autorefresh": True,
            "configrsc": config_rsc,
        }
        if output_names:
            modio_kwargs["monitoring"] = False
            modio_kwargs["shared_procimg"] = True
            logging.warning(
                "DIO output control is enabled for %s; this app may write those outputs",
                ", ".join(output_names),
            )
        else:
            modio_kwargs["monitoring"] = True

        self.rpi = revpimodio2.RevPiModIO(
            **modio_kwargs,
        )
        self.inputs = self._resolve_ios(input_names, "input")
        self.counters = self._resolve_ios(counter_names, "counter")
        self.outputs = self._resolve_ios(output_names, "output")
        if not self.inputs and not self.counters and not self.outputs:
            raise RuntimeError(
                "none of the configured DIO inputs, counters, or outputs were found; "
                "check DIO_INPUT_NAMES, DIO_COUNTER_NAMES, and DIO_OUTPUT_NAMES"
            )

    def _resolve_ios(self, names, label):
        ios = {}
        for name in names:
            try:
                ios[name] = getattr(self.rpi.io, name)
            except AttributeError:
                logging.warning("PiCtory %s %s not found", label, name)
        return ios

    def read(self):
        with self.lock:
            states = {name: bool(io.value) for name, io in self.inputs.items()}
            counters = {name: int(io.value) for name, io in self.counters.items()}
            outputs = {name: bool(io.value) for name, io in self.outputs.items()}
        return states, counters, outputs

    def set_output(self, name, state):
        with self.lock:
            if name not in self.outputs:
                raise KeyError(f"output {name} is not configured")
            self.outputs[name].value = bool(state)
            return bool(self.outputs[name].value)

    def reset_counters(self):
        with self.lock:
            for name, io in self.counters.items():
                reset = getattr(io, "reset", None)
                if reset is None:
                    logging.warning("counter %s does not expose reset()", name)
                    continue
                logging.info("resetting counter %s", name)
                try:
                    reset()
                except Exception as exc:
                    logging.warning("failed to reset counter %s: %s", name, exc)

    def close(self):
        exit_fn = getattr(self.rpi, "exit", None)
        if exit_fn is not None:
            exit_fn()


def build_reader(input_names, counter_names, output_names):
    if env_bool("SIMULATE_INPUTS", False):
        logging.warning("SIMULATE_INPUTS is enabled; not reading /dev/piControl0")
        return SimulatedReader(input_names, counter_names, output_names)
    return RevPiReader(input_names, counter_names, output_names)


def counter_delta(previous, current):
    if previous is None:
        return 0
    if current >= previous:
        return current - previous
    # Counters can be reset from PiCtory, piControl ioctl, or revpimodio2.reset().
    return current


def main():
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )

    data_dir = Path(os.environ.get("DATA_DIR", "/data"))
    data_dir.mkdir(parents=True, exist_ok=True)
    state_path = data_dir / "state.json"
    latest_path = data_dir / "latest.json"
    legacy_data_dir = os.environ.get("LEGACY_DATA_DIR")
    legacy_state_path = Path(legacy_data_dir) / "state.json" if legacy_data_dir else None

    input_names = parse_names(os.environ.get("DIO_INPUT_NAMES", "I_1,I_2,I_3,I_4"))
    counter_names = parse_names(
        os.environ.get("DIO_COUNTER_NAMES", "Counter_1,Counter_2,Counter_3,Counter_4")
    )
    output_names = parse_names(os.environ.get("DIO_OUTPUT_NAMES", "O_1,O_2,O_3,O_4"))
    if not input_names and not counter_names and not output_names:
        raise RuntimeError("configure at least one DIO input, counter, or output")

    poll_interval = float(os.environ.get("POLL_INTERVAL_SECONDS", "0.5"))
    app_schema_version = os.environ.get("APP_SCHEMA_VERSION", "2")
    web_bind = os.environ.get("WEB_BIND", "0.0.0.0")
    web_port = int(os.environ.get("WEB_PORT", "8090"))

    state = load_state(state_path, legacy_state_path)
    last_counter_values = {
        name: int(value) for name, value in state.get("lastCounterValues", {}).items()
    }
    last_counter_seen_at = {
        name: float(value) for name, value in state.get("lastCounterSeenAt", {}).items()
    }

    store = InfluxStore(
        url=os.environ.get("INFLUX_URL", "http://influxdb:8086"),
        token=os.environ.get("INFLUX_TOKEN", "revpi-dio-token"),
        org=os.environ.get("INFLUX_ORG", "revpi"),
        bucket=os.environ.get("INFLUX_BUCKET", "revpi_dio"),
    )
    store.wait_until_ready()
    store.ensure_bucket()
    store.ensure_schema_marker(app_schema_version)

    reader = build_reader(input_names, counter_names, output_names)
    if env_bool("RESET_COUNTERS_ON_START", False):
        reader.reset_counters()
        last_counter_values.clear()
        last_counter_seen_at.clear()

    runtime_state = RuntimeState(input_names, counter_names, output_names)
    web_server = start_web_server(web_bind, web_port, runtime_state, reader)

    stop = False

    def request_stop(signum, _frame):
        nonlocal stop
        logging.info("received signal %s", signum)
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    if input_names:
        logging.info("tracking DIO inputs: %s", ", ".join(input_names))
    if counter_names:
        logging.info("tracking DIO counters: %s", ", ".join(counter_names))
    if output_names:
        logging.info("controlling DIO outputs: %s", ", ".join(output_names))

    last_state_write = 0.0

    try:
        while not stop:
            sample_time = utc_now()
            monotonic_now = time.monotonic()
            states, counters, outputs = reader.read()
            points = []
            latest_inputs = {}
            latest_counters = {}
            latest_outputs = {}

            for name, value in states.items():
                latest_inputs[name] = {"state": int(value)}
                points.append(
                    Point("revpi_dio_input")
                    .tag("input", name)
                    .field("state", int(value))
                    .time(sample_time, WritePrecision.NS)
                )

            for name, value in counters.items():
                previous_value = last_counter_values.get(name)
                previous_seen_at = last_counter_seen_at.get(name)
                delta = counter_delta(previous_value, value)
                elapsed = (
                    monotonic_now - previous_seen_at
                    if previous_seen_at is not None and monotonic_now > previous_seen_at
                    else 0.0
                )
                pulses_per_minute = delta * 60.0 / elapsed if elapsed > 0 else 0.0

                last_counter_values[name] = value
                last_counter_seen_at[name] = monotonic_now
                latest_counters[name] = {
                    "value": value,
                    "delta": delta,
                    "pulsesPerMinute": pulses_per_minute,
                }
                points.append(
                    Point("revpi_dio_counter")
                    .tag("counter", name)
                    .field("value", value)
                    .field("delta", delta)
                    .field("pulses_per_minute", pulses_per_minute)
                    .time(sample_time, WritePrecision.NS)
                )

            for name, value in outputs.items():
                latest_outputs[name] = {"state": int(value)}

            store.write(points)
            latest = {
                "timestamp": isoformat(sample_time),
                "inputs": latest_inputs,
                "counters": latest_counters,
                "outputs": latest_outputs,
                "schemaVersion": LOCAL_STATE_SCHEMA_VERSION,
            }
            runtime_state.update(latest)
            atomic_write_json(latest_path, latest)

            if monotonic_now - last_state_write > 30:
                atomic_write_json(
                    state_path,
                    {
                        "schemaVersion": LOCAL_STATE_SCHEMA_VERSION,
                        "lastCounterValues": last_counter_values,
                        "lastCounterSeenAt": last_counter_seen_at,
                    },
                )
                last_state_write = monotonic_now

            time.sleep(poll_interval)
    finally:
        if web_server is not None:
            web_server.shutdown()
            web_server.server_close()
        atomic_write_json(
            state_path,
            {
                "schemaVersion": LOCAL_STATE_SCHEMA_VERSION,
                "lastCounterValues": last_counter_values,
                "lastCounterSeenAt": last_counter_seen_at,
            },
        )
        reader.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        logging.exception("controller failed: %s", exc)
        sys.exit(1)
