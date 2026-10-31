#!/usr/bin/env python3
"""Run shadow-mode ML job templates against real events stored in OpenSearch.

Each job in config/ml/jobs/ names the indices and query to read, the entity to
group by (for example source.ip), and the metric to measure per time window.
Every entity is compared with its own history: the baseline period sets what
is normal, and recent windows far above normal are flagged as anomalous.
Anomalies (and a run summary per job) are written to the ML results index so
they appear in the "Net Sec Watch - ML Findings" dashboard. Nothing is blocked.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from statistics import mean, pstdev

ROOT = Path(__file__).resolve().parents[1]
JOBS_DIR = ROOT / "config/ml/jobs"
PAGE_SIZE = 1000
MAX_PAGES = 500
REQUIRED = ("id", "version", "title", "source", "entity_field", "metric",
            "window_minutes", "baseline_days", "evaluation_hours", "thresholds")


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_job(path: Path) -> dict:
    job = json.loads(path.read_text(encoding="utf-8"))
    missing = [key for key in REQUIRED if key not in job]
    if missing:
        raise ValueError(f"{path}: missing {', '.join(missing)}")
    if job.get("shadow_mode") is not True:
        raise ValueError(f"{path}: shadow_mode must be true; jobs only suggest, never act")
    if job["metric"].get("type") not in ("count", "distinct"):
        raise ValueError(f"{path}: metric.type must be count or distinct")
    if job["metric"]["type"] == "distinct" and not job["metric"].get("field"):
        raise ValueError(f"{path}: a distinct metric needs metric.field")
    for key in ("window_minutes", "baseline_days", "evaluation_hours"):
        if not isinstance(job[key], int) or job[key] <= 0:
            raise ValueError(f"{path}: {key} must be a positive whole number")
    if job["evaluation_hours"] * 60 < job["window_minutes"]:
        raise ValueError(f"{path}: evaluation_hours must cover at least one window")
    if not job["source"].get("indices") or not job["source"].get("query"):
        raise ValueError(f"{path}: source needs indices and query")
    return job


def job_paths(args) -> list[Path]:
    if args.all:
        return sorted(JOBS_DIR.glob("*.json"))
    paths = []
    for name in args.job:
        candidate = Path(name)
        if not candidate.exists():
            candidate = JOBS_DIR / (name if name.endswith(".json") else name + ".json")
        if not candidate.exists():
            raise ValueError(f"Job not found: {name}. Run with --list to see available jobs.")
        paths.append(candidate)
    return paths


class OpenSearch:
    def __init__(self, args):
        self.endpoint = args.endpoint.rstrip("/")
        self.timeout = args.timeout
        self.headers = {"Content-Type": "application/json"}
        if args.password:
            basic = base64.b64encode(f"{args.username}:{args.password}".encode()).decode()
            self.headers["Authorization"] = "Basic " + basic
        if args.insecure:
            self.context = ssl._create_unverified_context()
        else:
            self.context = ssl.create_default_context(cafile=args.ca_file or None)

    def request(self, method: str, path: str, body: bytes | None = None,
                content_type: str = "application/json") -> dict:
        headers = dict(self.headers, **{"Content-Type": content_type})
        request = urllib.request.Request(self.endpoint + path, data=body,
                                         headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout,
                                        context=self.context) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")[:500]
            raise ValueError(f"OpenSearch returned {error.code} for {path}: {detail}") from error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            raise ValueError(f"Cannot reach OpenSearch at {self.endpoint} ({error}). "
                             "Start the stack with make setup, or set OPENSEARCH_ENDPOINT.") from error


def time_range(job: dict, now: datetime) -> tuple[int, int, int, int]:
    """Return window size, start, evaluation start, and end in epoch ms, window aligned."""
    window = job["window_minutes"] * 60_000
    now_ms = int(now.timestamp() * 1000)
    end = now_ms // window * window  # leave out the current, still-filling window
    evaluation_start = (now_ms - job["evaluation_hours"] * 3_600_000) // window * window
    start = (evaluation_start - job["baseline_days"] * 86_400_000) // window * window
    return window, start, evaluation_start, end


def aggregatable_field(client: OpenSearch, indices: str, field: str) -> str:
    """Return a field name that can be grouped on.

    The secure stack's index template maps fields like source.ip as ip or
    keyword. The local HTTP stack has no template, so OpenSearch maps strings
    as text with a .keyword subfield; grouping must use that subfield.
    """
    path = (f"/{indices}/_field_caps?fields={field},{field}.keyword"
            "&ignore_unavailable=true&allow_no_indices=true")
    caps = client.request("GET", path).get("fields", {})
    if field not in caps or all(t.get("aggregatable") for t in caps[field].values()):
        return field  # aggregatable, or not present yet (the query then finds nothing)
    keyword = caps.get(f"{field}.keyword", {})
    if keyword and all(t.get("aggregatable") for t in keyword.values()):
        return f"{field}.keyword"
    raise ValueError(f"{field} is mapped as text in {indices} and cannot be grouped on. "
                     "Pick a keyword or IP field, or install the index template.")


def fetch_series(client: OpenSearch, job: dict, window: int, start: int, end: int) -> dict:
    """Return {entity: {window_start_ms: value}} for non-empty windows."""
    indices = job["source"]["indices"]
    composite = {
        "size": PAGE_SIZE,
        "sources": [
            {"entity": {"terms": {"field": aggregatable_field(client, indices, job["entity_field"])}}},
            {"window": {"date_histogram": {"field": "@timestamp",
                                           "fixed_interval": f"{job['window_minutes']}m"}}},
        ],
    }
    metric = job["metric"]
    aggs = {"series": {"composite": composite}}
    if metric["type"] == "distinct":
        distinct_field = aggregatable_field(client, indices, metric["field"])
        aggs["series"]["aggs"] = {"value": {"cardinality": {"field": distinct_field}}}
    body = {
        "size": 0,
        "track_total_hits": False,
        "query": {"bool": {"filter": [
            {"range": {"@timestamp": {"gte": start, "lt": end, "format": "epoch_millis"}}},
            {"query_string": {"query": job["source"]["query"]}},
        ]}},
        "aggs": aggs,
    }
    path = "/" + job["source"]["indices"] + "/_search?ignore_unavailable=true&allow_no_indices=true"
    series: dict = {}
    for _ in range(MAX_PAGES):
        result = client.request("POST", path, json.dumps(body).encode())
        buckets = result.get("aggregations", {}).get("series", {}).get("buckets", [])
        for bucket in buckets:
            value = bucket["value"]["value"] if metric["type"] == "distinct" else bucket["doc_count"]
            series.setdefault(str(bucket["key"]["entity"]), {})[int(bucket["key"]["window"])] = value
        after = result.get("aggregations", {}).get("series", {}).get("after_key")
        if not buckets or not after:
            return series
        composite["after"] = after
    print(f"  warning: stopped after {MAX_PAGES * PAGE_SIZE} buckets; "
          "narrow the job query or shorten baseline_days", file=sys.stderr)
    return series


def describe_metric(job: dict) -> str:
    metric = job["metric"]
    return "events" if metric["type"] == "count" else f"distinct {metric['field']} values"


def score(job: dict, series: dict, window: int, start: int, evaluation_start: int,
          end: int, scored_at: str) -> list[dict]:
    thresholds = job["thresholds"]
    baseline_windows = range(start, evaluation_start, window)
    results = []
    for entity, values in sorted(series.items()):
        baseline = [values.get(moment, 0) for moment in baseline_windows]
        normal = mean(baseline) if baseline else 0.0
        spread = pstdev(baseline) if len(baseline) > 1 else 0.0
        new_entity = not any(baseline)
        for moment in range(evaluation_start, end, window):
            observed = values.get(moment, 0)
            if not observed:
                continue
            z_score = (observed - normal) / (spread or 1.0)
            anomalous = z_score >= thresholds["z_score"] and observed >= thresholds["min_value"]
            value = max(0.0, min(1.0, z_score / 6.0))
            level = "high" if value >= 0.75 else "medium" if value >= 0.5 else "low"
            window_start = datetime.fromtimestamp(moment / 1000, timezone.utc)
            window_end = window_start + timedelta(milliseconds=window)
            verdict = "anomalous" if anomalous else "baseline"
            message = (f"{entity}: {observed} {describe_metric(job)} in {job['window_minutes']}m "
                       f"(normal {normal:.1f} ± {spread:.1f}, z={z_score:.1f}"
                       f"{', not seen in baseline' if new_entity else ''}) - {verdict}")
            investigate = f"({job['source']['query']}) AND {job['entity_field']}:\"{entity}\""
            doc_id = hashlib.sha256(f"{job['id']}|{entity}|{moment}".encode()).hexdigest()[:24]
            detail = {
                "job_id": job["id"], "job_version": job["version"], "entity_field": job["entity_field"],
                "entity": entity, "metric": job["metric"], "observed": observed,
                "baseline_mean": round(normal, 4), "baseline_stdev": round(spread, 4),
                "baseline_windows": len(baseline), "z_score": round(z_score, 4),
                "new_entity": new_entity, "window_start": iso(window_start),
                "window_end": iso(window_end), "indices": job["source"]["indices"],
                "investigate_query": investigate, "scored_at": scored_at,
            }
            record = {
                "@timestamp": iso(window_start),
                "event.kind": "prediction",
                "event.category": "ml",
                "event.dataset": f"ml.{job['id']}",
                "event.id": doc_id,
                "event.classification": verdict,
                "event.threat_score": round(value, 4),
                "event.threat_level": level,
                "event.ml_model_id": f"{job['id']}@{job['version']}",
                "event.correlation_key": f"{job['entity_field']}={entity}",
                "rule.id": job["id"],
                "rule.name": job["title"],
                "rule.category": "ml-shadow",
                "message": message,
                "event.original": json.dumps(detail, sort_keys=True),
            }
            if job["entity_field"] in ("source.ip", "destination.ip", "host.name"):
                record[job["entity_field"]] = entity
            results.append(record)
    return results


def run_record(job: dict, results: list[dict], entities: int, start: int, end: int,
               scored_at: str, indexed: int) -> dict:
    anomalies = sum(1 for item in results if item["event.classification"] == "anomalous")
    message = (f"{job['title']}: scored {len(results)} active windows for {entities} "
               f"{job['entity_field']} values, {anomalies} anomalous")
    return {
        "@timestamp": scored_at,
        "event.kind": "ml_job_run",
        "event.category": "ml",
        "event.dataset": f"ml.{job['id']}",
        "event.id": hashlib.sha256(f"run|{job['id']}|{scored_at}".encode()).hexdigest()[:24],
        "event.outcome": "success",
        "event.ml_model_id": f"{job['id']}@{job['version']}",
        "rule.id": job["id"],
        "rule.name": job["title"],
        "rule.category": "ml-shadow",
        "message": message,
        "event.original": json.dumps({
            "job_id": job["id"], "entities": entities, "windows_scored": len(results),
            "anomalies": anomalies, "indexed": indexed,
            "period_start": iso(datetime.fromtimestamp(start / 1000, timezone.utc)),
            "period_end": iso(datetime.fromtimestamp(end / 1000, timezone.utc)),
        }, sort_keys=True),
    }


def index_records(client: OpenSearch, index: str, records: list[dict]) -> int:
    """Create records with stable IDs; return how many were new.

    "create" works for both plain indices and data streams (the secure stack's
    template), and a rerun skips findings that were already recorded.
    """
    created = 0
    for offset in range(0, len(records), 1000):
        lines = []
        for record in records[offset:offset + 1000]:
            lines.append(json.dumps({"create": {"_id": record["event.id"]}}))
            lines.append(json.dumps(record, sort_keys=True))
        result = client.request("POST", f"/{index}/_bulk?refresh=true",
                                ("\n".join(lines) + "\n").encode(), "application/x-ndjson")
        failures = []
        for item in result.get("items", []):
            for entry in item.values():
                if not entry.get("error"):
                    created += 1
                elif entry.get("status") != 409:  # 409: already recorded by an earlier run
                    failures.append(entry["error"])
        if failures:
            raise ValueError(f"Indexing into {index} failed: {json.dumps(failures[:3])}")
    return created


def run_job(client: OpenSearch, job: dict, args, now: datetime) -> dict:
    window, start, evaluation_start, end = time_range(job, now)
    scored_at = iso(now)
    series = fetch_series(client, job, window, start, end)
    results = score(job, series, window, start, evaluation_start, end, scored_at)
    anomalies = [item for item in results if item["event.classification"] == "anomalous"]
    to_index = results if args.index_all_scores else anomalies
    indexed = 0
    if not args.no_index:
        indexed = index_records(client, args.results_index, to_index)
        summary = run_record(job, results, len(series), start, end, scored_at, indexed)
        index_records(client, args.results_index, [summary])
    outdir = args.output_dir / job["id"]
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "scores.jsonl").write_text("".join(json.dumps(item, sort_keys=True) + "\n"
                                                 for item in results), encoding="utf-8")
    lines = [f"{job['title']} ({job['id']}@{job['version']})",
             f"Read: {job['source']['indices']}  query: {job['source']['query']}",
             f"Baseline {job['baseline_days']}d, evaluated last {job['evaluation_hours']}h "
             f"in {job['window_minutes']}m windows.",
             f"{len(series)} {job['entity_field']} values, {len(results)} active windows, "
             f"{len(anomalies)} anomalous"
             + ("." if args.no_index else f", {indexed} newly recorded in {args.results_index}."), ""]
    lines += [item["message"] for item in sorted(anomalies, key=lambda r: -r["event.threat_score"])[:20]]
    if not series:
        lines.append("No matching events in this period. Check the query in Discover "
                     "and confirm logs are arriving (make ingestion-status).")
    (outdir / "summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join("  " + line if line else "" for line in lines))
    return {"job": job["id"], "entities": len(series), "windows": len(results),
            "anomalies": len(anomalies), "indexed": indexed}


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--job", action="append", help="job id or path to a job file (repeatable)")
    target.add_argument("--all", action="store_true", help="run every job in config/ml/jobs/")
    target.add_argument("--list", action="store_true", help="list available jobs and exit")
    parser.add_argument("--endpoint", default=os.environ.get("OPENSEARCH_ENDPOINT", "http://127.0.0.1:9200"))
    parser.add_argument("--username", default=os.environ.get("OPENSEARCH_USERNAME", "admin"))
    parser.add_argument("--password", default=os.environ.get("OPENSEARCH_PASSWORD")
                        or os.environ.get("OPENSEARCH_INITIAL_ADMIN_PASSWORD"))
    parser.add_argument("--ca-file", default=os.environ.get("OPENSEARCH_CA_FILE"))
    parser.add_argument("--insecure", action="store_true", help="skip TLS verification (lab only)")
    parser.add_argument("--results-index",
                        default=os.environ.get("ML_RESULTS_INDEX", "net-sec-watch-ml-development"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "runtime/ml-jobs")
    parser.add_argument("--no-index", action="store_true",
                        help="score and write local files only; don't write to OpenSearch")
    parser.add_argument("--index-all-scores", action="store_true",
                        help="index every scored window, not just anomalies")
    parser.add_argument("--every", type=int, metavar="MINUTES",
                        help="keep running, repeating every MINUTES")
    parser.add_argument("--now", help="score as if it were this ISO 8601 time (replays, tests)")
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args(argv)
    if args.every is not None and args.every <= 0:
        parser.error("--every must be a positive number of minutes")
    if args.now:
        try:
            args.now = datetime.fromisoformat(args.now.replace("Z", "+00:00"))
        except ValueError:
            parser.error("--now must be an ISO 8601 time, for example 2026-11-01T12:00:00Z")
        if args.now.tzinfo is None:
            parser.error("--now must include a timezone, for example Z")
    return args


def main(argv=None) -> int:
    args = parse_args(argv)
    if args.list:
        for path in sorted(JOBS_DIR.glob("*.json")):
            job = load_job(path)
            print(f"{job['id']:32} {job['title']}")
        return 0
    jobs = [load_job(path) for path in job_paths(args)]
    client = OpenSearch(args)
    while True:
        now = args.now or datetime.now(timezone.utc)
        print(f"ML jobs at {iso(now)} (shadow mode: results are suggestions only)")
        totals = []
        for job in jobs:
            print(f"\n- {job['id']}")
            try:
                totals.append(run_job(client, job, args, now))
            except ValueError as error:
                if args.every is None:
                    raise
                # Keep a scheduled loop alive through a temporary outage.
                print(f"  failed: {error} (retrying next run)", file=sys.stderr)
        flagged = sum(item["anomalies"] for item in totals)
        where = ("local files only" if args.no_index
                 else f"index {args.results_index}; open the 'Net Sec Watch - ML Findings' dashboard")
        print(f"\nDone: {flagged} anomalous windows across {len(totals)} jobs. "
              f"Results: {args.output_dir} and {where}.")
        if args.every is None:
            return 0
        time.sleep(args.every * 60)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as error:
        print(f"ML job failed: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
