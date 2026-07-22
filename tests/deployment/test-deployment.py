#!/usr/bin/env python3
"""Static deployment portability deployment portability contract checks."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_environment_and_compose_files() -> None:
    for env in ["development", "test", "staging", "production"]:
        path = ROOT / f"deploy/environments/{env}.env.example"
        assert_true(path.is_file(), f"{env} env example missing")
        assert_true(f"DEPLOYMENT_ENVIRONMENT={env}" in path.read_text(), f"{env} env not named")
    compose = read("deploy/compose/compose.production.yaml")
    for term in ["resources:", "limits:", "reservations:", "restart: always"]:
        assert_true(term in compose, f"production compose missing {term}")


def test_linux_and_kubernetes_deployment() -> None:
    assert_true((ROOT / "deploy/linux/install-linux-vm.sh").is_file(), "Linux installer missing")
    k8s_files = [
        "namespace.yaml",
        "serviceaccount.yaml",
        "rbac.yaml",
        "configmap.yaml",
        "secret.example.yaml",
        "persistentvolumeclaims.yaml",
        "deployment.yaml",
        "services.yaml",
        "networkpolicy.yaml",
    ]
    for name in k8s_files:
        assert_true((ROOT / f"deploy/kubernetes/{name}").is_file(), f"{name} missing")
    deployment = read("deploy/kubernetes/deployment.yaml")
    for term in ["resources:", "requests:", "limits:", "serviceAccountName"]:
        assert_true(term in deployment, f"Kubernetes deployment missing {term}")
    pvc = read("deploy/kubernetes/persistentvolumeclaims.yaml")
    assert_true("storageClassName" in pvc, "PVC storage class missing")
    network = read("deploy/kubernetes/networkpolicy.yaml")
    assert_true("podSelector: {}" in network, "default deny policy missing")
    assert_true("allow-collector-to-opensearch" in network, "collector allow policy missing")


def test_preflight_upgrade_rollback_and_docs() -> None:
    for script in [
        "scripts/preflight-deployment.sh",
        "scripts/upgrade-release.sh",
        "scripts/rollback-release.sh",
    ]:
        assert_true((ROOT / script).is_file(), f"{script} missing")
    for doc in [
        "docs/deployment-portability.md",
        "docs/installation-administration-troubleshooting.md",
        "docs/supported-versions.md",
        "docs/production-readiness-review.md",
        "docs/release-checklist.md",
        "docs/runbooks/backup-restore.md",
    ]:
        assert_true((ROOT / doc).is_file(), f"{doc} missing")


def test_open_source_runtime_policy() -> None:
    supported = read("docs/supported-versions.md")
    for component in [
        "Fluent Bit",
        "OpenSearch",
        "OpenSearch Dashboards",
        "Keycloak",
        "Zeek",
        "Suricata",
    ]:
        assert_true(component in supported, f"{component} missing from support policy")
    assert_true("Open source, self-hostable" in supported, "open-source runtime policy missing")


def test_feature_status_boundary() -> None:
    status = read("docs/features-and-roadmap.md")
    assert_true(
        "Tag and publish the first supported release" in status,
        "tag/publish should remain open until explicitly performed",
    )
    assert_true(
        "open-source runtime policy" in status,
        "open-source runtime gate should be complete",
    )


if __name__ == "__main__":
    for test in [
        test_environment_and_compose_files,
        test_linux_and_kubernetes_deployment,
        test_preflight_upgrade_rollback_and_docs,
        test_open_source_runtime_policy,
        test_feature_status_boundary,
    ]:
        test()
    print("Deployment contract is valid.")
