#!/usr/bin/env python3
"""Run ML job templates against a stand-in OpenSearch that aggregates real events."""

import importlib.util
import io
import json
import tempfile
import threading
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ml_run_job", ROOT / "scripts/ml-run-job.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
runner.PAGE_SIZE = 50  # force several pages so pagination is exercised

NOW = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)


def ms(moment):
    return int(moment.timestamp() * 1000)


def build_events():
    events = []
    # 192.0.2.10: 1-2 denies most hours for the 7-day baseline, then a 40-deny burst.
    for hour in range(24 * 8):
        moment = NOW - timedelta(hours=hour, minutes=5)
        for _ in range(1 + hour % 2):
            events.append({"@timestamp": ms(moment), "source.ip": "192.0.2.10",
                           "destination.port": 443})
    burst = NOW - timedelta(hours=2, minutes=7)
    for number in range(40):
        events.append({"@timestamp": ms(burst), "source.ip": "192.0.2.10",
                       "destination.port": 1000 + number})
    # 192.0.2.20: never seen before, a few denies (below min_value, so not flagged).
    for _ in range(3):
        events.append({"@timestamp": ms(NOW - timedelta(hours=1)), "source.ip": "192.0.2.20",
                       "destination.port": 22})
    # An old event outside the window must be ignored.
    events.append({"@timestamp": ms(NOW - timedelta(days=30)), "source.ip": "192.0.2.99",
                   "destination.port": 22})
    return events


class FakeOpenSearch(BaseHTTPRequestHandler):
    events = build_events()
    documents = {}
    searches = []
    text_fields = set()  # simulate the local stack's dynamic text mapping
    auth_headers = set()

    def log_message(self, *args):
        pass

    def reply(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        assert "/_field_caps" in self.path
        fields = self.path.split("fields=")[1].split("&")[0].split(",")
        caps = {}
        for field in fields:
            base = field.removesuffix(".keyword")
            if base in self.text_fields:
                caps[field] = ({"keyword": {"aggregatable": True}} if field.endswith(".keyword")
                               else {"text": {"aggregatable": False}})
            elif not field.endswith(".keyword"):
                caps[field] = {"ip": {"aggregatable": True}}
        self.reply({"fields": caps})

    def do_POST(self):
        self.auth_headers.add(self.headers.get("Authorization"))
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        if "/_bulk" in self.path:
            lines = [json.loads(line) for line in body.splitlines() if line]
            items = []
            for action, document in zip(lines[::2], lines[1::2]):
                assert "create" in action, "writes must use create (data-stream safe)"
                doc_id = action["create"]["_id"]
                if doc_id in self.documents:
                    items.append({"create": {"status": 409, "error": {"type": "version_conflict"}}})
                else:
                    self.documents[doc_id] = document
                    items.append({"create": {"status": 201}})
            return self.reply({"errors": any("error" in i["create"] for i in items), "items": items})
        request = json.loads(body)
        self.searches.append((self.path, request))
        window_range = request["query"]["bool"]["filter"][0]["range"]["@timestamp"]
        composite = request["aggs"]["series"]["composite"]
        interval = int(composite["sources"][1]["window"]["date_histogram"]["fixed_interval"][:-1]) * 60_000
        entity_field = composite["sources"][0]["entity"]["terms"]["field"]
        if entity_field.removesuffix(".keyword") in self.text_fields:
            assert entity_field.endswith(".keyword"), "text fields must be grouped via .keyword"
        else:
            assert not entity_field.endswith(".keyword")
        entity_field = entity_field.removesuffix(".keyword")
        distinct = request["aggs"]["series"].get("aggs", {}).get("value", {}).get("cardinality", {}).get("field")
        groups = {}
        for event in self.events:
            if window_range["gte"] <= event["@timestamp"] < window_range["lt"] and entity_field in event:
                key = (event[entity_field], event["@timestamp"] // interval * interval)
                groups.setdefault(key, []).append(event)
        keys = sorted(groups)
        if "after" in composite:
            after = (composite["after"]["entity"], composite["after"]["window"])
            keys = [key for key in keys if key > after]
        page = keys[:composite["size"]]
        buckets = []
        for entity, window in page:
            bucket = {"key": {"entity": entity, "window": window}, "doc_count": len(groups[(entity, window)])}
            if distinct:
                bucket["value"] = {"value": len({e[distinct] for e in groups[(entity, window)]})}
            buckets.append(bucket)
        series = {"buckets": buckets}
        if page:
            series["after_key"] = {"entity": page[-1][0], "window": page[-1][1]}
        self.reply({"aggregations": {"series": series}})


def run(*args):
    out = io.StringIO()
    with redirect_stdout(out):
        assert runner.main(list(args)) == 0
    return out.getvalue()


def main():
    # Every shipped template must load and be in shadow mode.
    jobs = sorted((ROOT / "config/ml/jobs").glob("*.json"))
    assert len(jobs) >= 4
    for path in jobs:
        job = runner.load_job(path)
        assert job["id"] == path.stem

    server = ThreadingHTTPServer(("127.0.0.1", 0), FakeOpenSearch)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    endpoint = f"http://127.0.0.1:{server.server_port}"
    try:
        with tempfile.TemporaryDirectory() as tmp:
            common = ["--endpoint", endpoint, "--now", NOW.isoformat(), "--output-dir", tmp]
            output = run("--job", "firewall-denies-per-source", "--job", "port-fanout-per-source", *common)
            assert "192.0.2.10" in output

            findings = [d for d in FakeOpenSearch.documents.values() if d["event.kind"] == "prediction"]
            runs = [d for d in FakeOpenSearch.documents.values() if d["event.kind"] == "ml_job_run"]
            assert len(runs) == 2
            by_job = {d["rule.id"]: d for d in findings}
            assert set(by_job) == {"firewall-denies-per-source", "port-fanout-per-source"}, by_job
            for finding in findings:
                assert finding["event.classification"] == "anomalous"
                assert finding["source.ip"] == "192.0.2.10"
                detail = json.loads(finding["event.original"])
                assert detail["baseline_windows"] == 7 * 24 * 6
                assert "source.ip:\"192.0.2.10\"" in detail["investigate_query"]
            assert all("192.0.2.20" not in d["message"] for d in findings), "below min_value"
            assert "192.0.2.99" not in json.dumps(FakeOpenSearch.documents), "outside period"

            # Pagination ran over several pages for the 7-day baseline.
            assert len(FakeOpenSearch.searches) > 4

            # Local scores include non-anomalous windows; new entity is marked.
            scores = [json.loads(line) for line in
                      (Path(tmp) / "firewall-denies-per-source/scores.jsonl").read_text().splitlines()]
            new = [s for s in scores if s.get("source.ip") == "192.0.2.20"]
            assert new and json.loads(new[0]["event.original"])["new_entity"] is True
            assert new[0]["event.classification"] == "baseline"

            # Rerunning must not duplicate findings.
            before = len(findings)
            run("--job", "firewall-denies-per-source", "--job", "port-fanout-per-source", *common)
            after = [d for d in FakeOpenSearch.documents.values() if d["event.kind"] == "prediction"]
            assert len(after) == before

            # Local stack: source.ip is text, so grouping uses source.ip.keyword
            # and finds the same anomaly. Credentials are sent when given.
            FakeOpenSearch.text_fields = {"source.ip"}
            output = run("--job", "firewall-denies-per-source", "--no-index",
                         "--username", "admin", "--password", "example-only", *common)
            assert "192.0.2.10: 41 events" in output, output
            assert any(h and h.startswith("Basic ") for h in FakeOpenSearch.auth_headers)
            FakeOpenSearch.text_fields = set()

            # --no-index writes nothing to OpenSearch.
            count = len(FakeOpenSearch.documents)
            run("--job", "log-volume-per-host", "--no-index", *common)
            assert len(FakeOpenSearch.documents) == count
    finally:
        server.shutdown()

    # Unsafe or malformed templates are rejected.
    with tempfile.TemporaryDirectory() as tmp:
        bad = json.loads((ROOT / "config/ml/jobs/firewall-denies-per-source.json").read_text())
        bad["shadow_mode"] = False
        path = Path(tmp) / "bad.json"
        path.write_text(json.dumps(bad))
        try:
            runner.load_job(path)
        except ValueError as error:
            assert "shadow_mode" in str(error)
        else:
            raise AssertionError("non-shadow job accepted")

    print("ML job templates score real-event aggregations and record findings safely.")


if __name__ == "__main__":
    main()
