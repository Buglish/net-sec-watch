#!/usr/bin/env python3
"""Static Phase 7 reliability and operations contract checks."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def load_json(path: str):
    return json.loads(read(path))


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_monitoring_thresholds() -> None:
    thresholds = load_json("config/operations/monitoring-thresholds-v1.json")
    required = {
        "collector_events_accepted",
        "collector_events_dropped",
        "collector_events_retried",
        "collector_events_buffered",
        "collector_events_failed",
        "collector_silence",
        "source_volume_change",
        "queue_depth",
        "rejected_writes",
        "shard_health",
        "disk_watermark",
        "snapshot_failure",
        "certificate_expiry",
    }
    assert_true(required <= set(thresholds["metrics"]), "monitoring gaps")
    for metric in required:
        definition = thresholds["metrics"][metric]
        assert_true(definition["warning"], f"{metric} missing warning")
        assert_true(definition["critical"], f"{metric} missing critical")


def test_alerts_have_runbooks_and_owners() -> None:
    alerts = load_json("config/operations/alert-rules-v1.json")
    routes = alerts["routes"]
    seen = set()
    for alert in alerts["alerts"]:
        seen.add(alert["signal"])
        assert_true(alert["route"] in routes, f"{alert['id']} route missing")
        runbook = alert["runbook"]
        assert_true((ROOT / runbook).is_file(), f"{runbook} missing")
        assert_true(alert["condition"], f"{alert['id']} condition missing")
    for signal in {
        "collector_events_dropped",
        "collector_events_retried",
        "collector_events_buffered",
        "collector_silence",
        "source_volume_change",
        "rejected_writes",
        "shard_health",
        "disk_watermark",
        "snapshot_failure",
        "certificate_expiry",
    }:
        assert_true(signal in seen, f"alert missing for {signal}")


def test_runbooks_cover_phase_7_scenarios() -> None:
    runbooks = {
        "docs/runbooks/collector-backlog-and-parser-failure.md": [
            "backlog",
            "parser",
            "dead-letter",
        ],
        "docs/runbooks/opensearch-failure-disk-mapping.md": [
            "node",
            "disk",
            "mapping",
        ],
        "docs/runbooks/backup-restore.md": [
            "snapshot",
            "restore",
            "RPO",
        ],
        "docs/runbooks/certificate-and-secret-rotation.md": [
            "Certificate",
            "Secret",
            "make test-oidc",
        ],
        "docs/runbooks/load-testing.md": [
            "1.5",
            "make load-test-syslog",
            "Pass criteria",
        ],
        "docs/runbooks/failure-testing.md": [
            "collector",
            "network",
            "OpenSearch",
        ],
        "docs/runbooks/rolling-upgrade-and-rollback.md": [
            "Upgrade",
            "Rollback",
            "snapshot",
        ],
        "docs/runbooks/disaster-recovery-exercise.md": [
            "RTO",
            "RPO",
            "restore",
        ],
    }
    for path, terms in runbooks.items():
        content = read(path)
        for term in terms:
            assert_true(term in content, f"{path} missing {term}")


def test_service_levels_and_commands() -> None:
    levels = load_json("config/operations/service-levels-v1.json")
    targets = levels["targets"]
    assert_true(targets["rto"] == "4 hours", "RTO target changed")
    assert_true(targets["rpo"] == "24 hours", "RPO target changed")
    assert_true(targets["load_test_multiplier"] >= 1.5, "load test too low")
    assert_true(levels["owners"]["primary"] == "SecOps", "primary owner missing")

    makefile = read("Makefile")
    for target in [
        "test-phase7-operations",
        "load-test-syslog",
        "dr-exercise",
    ]:
        assert_true(f"{target}:" in makefile, f"Makefile missing {target}")

    for script in [
        "scripts/operations-health-check.py",
        "scripts/load-test-syslog.sh",
        "scripts/disaster-recovery-exercise.sh",
    ]:
        assert_true((ROOT / script).is_file(), f"{script} missing")


def test_feature_status_mentions_operations_boundaries() -> None:
    status = read("docs/features-and-roadmap.md")
    assert_true("Operations and disaster recovery" in status, "operations status missing")
    for remaining in [
        "Production service-level targets met under agreed load",
        "Documented disaster-recovery exercise meeting approved RTO/RPO",
        "Operator confirmation that critical alerts are diagnosable using runbooks",
    ]:
        assert_true(remaining in status, f"remaining-work boundary missing {remaining}")


if __name__ == "__main__":
    for test in [
        test_monitoring_thresholds,
        test_alerts_have_runbooks_and_owners,
        test_runbooks_cover_phase_7_scenarios,
        test_service_levels_and_commands,
        test_feature_status_mentions_operations_boundaries,
    ]:
        test()
    print("Phase 7 operations contract is valid.")
