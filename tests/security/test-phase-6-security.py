#!/usr/bin/env python3
"""Static Phase 6 security contract checks."""

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


def test_roles_and_mappings() -> None:
    roles = load_json("config/opensearch-security/roles-v1.json")
    mappings = load_json("config/opensearch-security/roles-mapping-v1.json")
    required = {
        "net_sec_watch_admin": "net-sec-watch-admin",
        "net_sec_watch_analyst": "net-sec-watch-analyst",
        "net_sec_watch_read_only": "net-sec-watch-read-only",
        "net_sec_watch_source_owner": "net-sec-watch-source-owner",
        "net_sec_watch_service": "net-sec-watch-service",
    }
    assert_true(set(required) <= set(roles), "missing Phase 6 roles")
    assert_true(set(required) <= set(mappings), "missing Phase 6 mappings")
    for role, backend_role in required.items():
        assert_true(
            backend_role in mappings[role]["backend_roles"],
            f"{role} is not mapped to {backend_role}",
        )

    assert_true(
        roles["net_sec_watch_admin"]["cluster_permissions"] == ["cluster_all"],
        "administrator must be the only cluster_all role",
    )
    for role, definition in roles.items():
        if role != "net_sec_watch_admin":
            assert_true(
                "cluster_all" not in definition.get("cluster_permissions", []),
                f"{role} must not have cluster_all",
            )

    service_actions = set(
        roles["net_sec_watch_service"]["index_permissions"][0][
            "allowed_actions"
        ]
    )
    assert_true("write" in service_actions, "service role must ingest")
    assert_true("read" not in service_actions, "service role must not search")
    assert_true("search" not in service_actions, "service role must not search")


def test_data_restrictions() -> None:
    roles = load_json("config/opensearch-security/roles-v1.json")
    read_only = roles["net_sec_watch_read_only"]["index_permissions"][0]
    source_owner = roles["net_sec_watch_source_owner"]["index_permissions"][0]
    analyst = roles["net_sec_watch_analyst"]["index_permissions"][0]

    assert_true("fls" in read_only, "read-only role needs field restrictions")
    assert_true(
        any(field.startswith("~event.original") for field in read_only["fls"]),
        "read-only role must hide raw event",
    )
    assert_true("dls" in source_owner, "source-owner role needs DLS")
    assert_true(
        "source.owner" in source_owner["dls"],
        "source-owner DLS must scope source.owner",
    )
    assert_true(
        "masked_fields" in analyst and analyst["masked_fields"],
        "analyst role needs masked sensitive fields",
    )
    assert_true(
        "net-sec-watch-audit-*" in roles["net_sec_watch_service"][
            "index_permissions"
        ][0]["index_patterns"],
        "service role must be able to write audit evidence streams",
    )


def test_identity_realm() -> None:
    realm = load_json("config/identity/net-sec-watch-realm.json")
    realm_roles = {role["name"] for role in realm["roles"]["realm"]}
    expected = {
        "net-sec-watch-admin",
        "net-sec-watch-analyst",
        "net-sec-watch-read-only",
        "net-sec-watch-source-owner",
        "net-sec-watch-service",
    }
    assert_true(expected <= realm_roles, "Keycloak realm missing roles")
    users = {user["username"]: user for user in realm["users"]}
    for username in {
        "oidc-test-admin",
        "oidc-test-analyst",
        "oidc-test-read-only",
        "oidc-test-source-owner",
        "oidc-test-service",
    }:
        assert_true(username in users, f"missing {username}")
    assert_true(
        users["oidc-test-source-owner"]["attributes"]["source_owner"],
        "source-owner user needs a source_owner attribute",
    )


def test_audit_and_review() -> None:
    audit = load_json("config/opensearch-security/audit-v1.json")
    assert_true(audit["config"]["enabled"], "audit logging must be enabled")
    assert_true(
        audit["config"]["audit"]["enable_rest"], "REST audit logging disabled"
    )
    assert_true(
        audit["config"]["audit"]["enable_transport"],
        "transport audit logging disabled",
    )
    assert_true(
        audit["config"]["compliance"]["enabled"],
        "compliance audit logging disabled",
    )
    watched_indices = audit["config"]["compliance"]["write_watched_indices"]
    assert_true(
        ".opendistro_security" in watched_indices,
        "security config changes must be audited",
    )
    review = load_json("config/security/security-review-findings-v1.json")
    assert_true(review["status"] == "accepted", "security review not accepted")
    assert_true(review["findings"] == [], "open security findings remain")


def test_redaction_wiring() -> None:
    lua = read("config/scripts/sensitive_redaction.lua")
    assert_true("redact_sensitive_fields" in lua, "redaction entrypoint missing")
    for term in ["authorization", "cookie", "password", "secret", "token"]:
        assert_true(term in lua, f"redaction does not cover {term}")
    for config in [
        "config/fluent-bit.conf",
        "config/fluent-bit.opensearch.conf.example",
    ]:
        content = read(config)
        redaction_position = content.index("sensitive_redaction.lua")
        output_position = content.index("[OUTPUT]")
        assert_true(
            redaction_position < output_position,
            f"redaction must run before outputs in {config}",
        )


def test_classification_rotation_and_supply_chain() -> None:
    classification = load_json("config/security/data-classification-v1.json")
    assert_true(
        classification["source_onboarding_review"][
            "required_before_production"
        ],
        "source-onboarding review must be required",
    )
    assert_true(
        "restricted" in classification["classes"],
        "restricted data class missing",
    )

    rotation = read("docs/phase-6-secret-rotation.md")
    for term in ["OPENSEARCH_INITIAL_ADMIN_PASSWORD", "OIDC_CLIENT_SECRET"]:
        assert_true(term in rotation, f"rotation doc missing {term}")

    compose = read("compose.yaml")
    for service in [
        "audit-runtime-sbom",
        "audit-source-sbom",
        "audit-vulnerabilities",
    ]:
        assert_true(f"{service}:" in compose, f"{service} missing")
    audit_script = read("scripts/security-audit.sh")
    for artifact in ["spdx.json", "grype.json", "sha256", "security/audits"]:
        assert_true(artifact in audit_script, f"audit artifact missing {artifact}")
    licenses = load_json("config/security/approved-licenses-v1.json")
    assert_true(
        "Apache-2.0" in licenses["approved_license_ids"],
        "license policy missing approved open-source licenses",
    )


def test_objectives_completed() -> None:
    objectives = read("OBJECTIVES.md")
    phase6 = objectives.split("## Phase 6 - Security, privacy, and access control", 1)[1]
    phase6 = phase6.split("## Phase 7", 1)[0]
    unchecked = re.findall(r"^- \[ \] .+$", phase6, flags=re.MULTILINE)
    assert_true(not unchecked, f"Phase 6 still has unchecked items: {unchecked}")


if __name__ == "__main__":
    tests = [
        test_roles_and_mappings,
        test_data_restrictions,
        test_identity_realm,
        test_audit_and_review,
        test_redaction_wiring,
        test_classification_rotation_and_supply_chain,
        test_objectives_completed,
    ]
    for test in tests:
        test()
    print("Phase 6 security contract is valid.")
