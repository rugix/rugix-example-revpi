"""Poll RevPi DIO values, write them to InfluxDB, and serve the local control UI."""

import copy
import json
import logging
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

import revpimodio2
from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS


APP_NAME = "revpi-dio-grafana"
STATIC_DIR = Path(__file__).with_name("static")
DIO_INPUT_NAMES = ("I_1", "I_2", "I_3", "I_4")
DIO_COUNTER_NAMES = ("Counter_1", "Counter_2", "Counter_3", "Counter_4")
DIO_OUTPUT_NAMES = ("O_1", "O_2", "O_3", "O_4")
WEB_BIND = "0.0.0.0"
WEB_PORT = 8090
CONFIG_RSC = "/etc/revpi/config.rsc"
DIO_CONFIGURATION_MESSAGE = (
    "The DIO module needs to be configured in PiCtory. Save the configuration "
    "as the start configuration and reset the driver."
)


class DioConfigurationRequired(RuntimeError):
    pass


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


class InfluxStore:
    def __init__(self, url, token, org, bucket):
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

    def write(self, points):
        if points:
            self.write_api.write(bucket=self.bucket, org=self.org, record=points)


class RuntimeState:
    def __init__(self):
        self.lock = threading.RLock()
        self.payload = {
            "app": APP_NAME,
            "dio": {
                "configured": False,
                "message": DIO_CONFIGURATION_MESSAGE,
            },
            "timestamp": None,
            "inputs": {},
            "counters": {},
            "outputs": {},
        }

    def update(self, payload):
        with self.lock:
            self.payload = dict(payload)
            self.payload["app"] = APP_NAME
            self.payload["dio"] = {"configured": True, "message": None}

    def require_dio_configuration(self):
        with self.lock:
            self.payload = {
                "app": APP_NAME,
                "dio": {
                    "configured": False,
                    "message": DIO_CONFIGURATION_MESSAGE,
                },
                "timestamp": None,
                "inputs": {},
                "counters": {},
                "outputs": {},
            }

    def patch_output(self, name, state):
        with self.lock:
            outputs = self.payload.setdefault("outputs", {})
            outputs[name] = {"state": int(state)}
            self.payload["timestamp"] = isoformat(utc_now())

    def snapshot(self):
        with self.lock:
            return copy.deepcopy(self.payload)


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
            except DioConfigurationRequired as exc:
                write_json(
                    self,
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    {"error": str(exc)},
                )
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
    server = ThreadingHTTPServer((bind, port), make_web_handler(runtime_state, reader))
    thread = threading.Thread(target=server.serve_forever, name="web-ui", daemon=True)
    thread.start()
    logging.info("serving DIO web UI on %s:%s", bind, port)
    return server


class RevPiReader:
    def __init__(self, input_names, counter_names, output_names):
        logging.info("using PiCtory config %s", CONFIG_RSC)
        self.lock = threading.RLock()
        logging.info(
            "DIO output control is enabled for %s; this app may write those outputs",
            ", ".join(output_names),
        )
        self.rpi = revpimodio2.RevPiModIO(
            autorefresh=True,
            configrsc=CONFIG_RSC,
            monitoring=False,
            shared_procimg=True,
        )
        try:
            self.inputs = self._resolve_ios(input_names, "input")
            self.counters = self._resolve_ios(counter_names, "counter")
            self.outputs = self._resolve_ios(output_names, "output")
            if not self.inputs and not self.counters and not self.outputs:
                raise RuntimeError(
                    "none of the expected DIO inputs, counters, or outputs were found; "
                    "check the PiCtory configuration"
                )
        except Exception:
            self.close()
            raise

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

    def close(self):
        exit_fn = getattr(self.rpi, "exit", None)
        if exit_fn is not None:
            exit_fn()


class RevPiDio:
    def __init__(self, input_names, counter_names, output_names):
        self.input_names = input_names
        self.counter_names = counter_names
        self.output_names = output_names
        self.lock = threading.RLock()
        self.reader = None

    def connect(self):
        reader = RevPiReader(
            self.input_names,
            self.counter_names,
            self.output_names,
        )
        with self.lock:
            self.reader = reader

    def is_connected(self):
        with self.lock:
            return self.reader is not None

    def read(self):
        with self.lock:
            if self.reader is None:
                raise DioConfigurationRequired(DIO_CONFIGURATION_MESSAGE)
            return self.reader.read()

    def set_output(self, name, state):
        with self.lock:
            if self.reader is None:
                raise DioConfigurationRequired(DIO_CONFIGURATION_MESSAGE)
            return self.reader.set_output(name, state)

    def disconnect(self):
        with self.lock:
            reader = self.reader
            self.reader = None
            if reader is not None:
                reader.close()

    def close(self):
        self.disconnect()


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

    poll_interval = float(os.environ.get("POLL_INTERVAL_SECONDS", "0.5"))
    dio_retry_interval = float(os.environ.get("DIO_RETRY_INTERVAL_SECONDS", "5"))
    last_counter_values = {}

    store = InfluxStore(
        url=os.environ.get("INFLUX_URL", "http://influxdb:8086"),
        token=os.environ.get("INFLUX_TOKEN", "revpi-dio-token"),
        org=os.environ.get("INFLUX_ORG", "revpi"),
        bucket=os.environ.get("INFLUX_BUCKET", "revpi_dio"),
    )
    store.wait_until_ready()
    store.ensure_bucket()

    runtime_state = RuntimeState()
    dio = RevPiDio(DIO_INPUT_NAMES, DIO_COUNTER_NAMES, DIO_OUTPUT_NAMES)
    web_server = start_web_server(WEB_BIND, WEB_PORT, runtime_state, dio)

    stop = False

    def request_stop(signum, _frame):
        nonlocal stop
        logging.info("received signal %s", signum)
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    logging.info("tracking DIO inputs: %s", ", ".join(DIO_INPUT_NAMES))
    logging.info("tracking DIO counters: %s", ", ".join(DIO_COUNTER_NAMES))
    logging.info("controlling DIO outputs: %s", ", ".join(DIO_OUTPUT_NAMES))

    next_dio_connection_attempt = time.monotonic()
    try:
        while not stop:
            if not dio.is_connected():
                now = time.monotonic()
                if now < next_dio_connection_attempt:
                    time.sleep(min(poll_interval, next_dio_connection_attempt - now))
                    continue
                try:
                    dio.connect()
                    last_counter_values.clear()
                    logging.info("DIO configuration loaded")
                except Exception as exc:
                    logging.warning("DIO configuration is not ready: %s", exc)
                    runtime_state.require_dio_configuration()
                    next_dio_connection_attempt = now + dio_retry_interval
                    continue

            sample_time = utc_now()
            try:
                states, counters, outputs = dio.read()
            except Exception as exc:
                logging.warning("lost access to the configured DIO: %s", exc)
                dio.disconnect()
                runtime_state.require_dio_configuration()
                next_dio_connection_attempt = time.monotonic() + dio_retry_interval
                continue
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
                delta = counter_delta(previous_value, value)

                last_counter_values[name] = value
                latest_counters[name] = {
                    "value": value,
                    "delta": delta,
                }
                points.append(
                    Point("revpi_dio_counter")
                    .tag("counter", name)
                    .field("value", value)
                    .field("delta", delta)
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
            }
            runtime_state.update(latest)

            time.sleep(poll_interval)
    finally:
        web_server.shutdown()
        web_server.server_close()
        dio.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        logging.exception("controller failed: %s", exc)
        sys.exit(1)
