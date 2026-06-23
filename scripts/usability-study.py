#!/usr/bin/env python3
"""Create, validate, and summarize Phase 5 usability-study sessions."""

import argparse
import json
import statistics
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = (
    ROOT / "config/dashboards/usability-scenarios-v1.json"
)


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_catalog(path=DEFAULT_CATALOG):
    return load_json(path)


def new_session(catalog, participant_id, profile):
    if profile not in catalog["approved_profiles"]:
        raise ValueError(f"unsupported participant profile: {profile}")
    return {
        "schema_version": 1,
        "study_id": catalog["study_id"],
        "participant": {
            "id": participant_id,
            "profile": profile,
            "prior_opensearch_experience": None,
        },
        "consent_confirmed": False,
        "started_at": None,
        "completed_at": None,
        "scenarios": [
            {
                "id": scenario["id"],
                "success": None,
                "completion_seconds": None,
                "assistance_count": 0,
                "server_access_used": False,
                "difficulty_rating": None,
                "notes": "",
            }
            for scenario in catalog["scenarios"]
        ],
        "post_study": {
            "confidence_rating": None,
            "would_use_without_help": None,
            "comments": "",
        },
    }


def require(condition, message, errors):
    if not condition:
        errors.append(message)


def validate_session(session, catalog):
    errors = []
    require(session.get("schema_version") == 1, "invalid schema_version", errors)
    require(
        session.get("study_id") == catalog["study_id"],
        "study_id does not match the catalog",
        errors,
    )
    participant = session.get("participant", {})
    require(bool(participant.get("id")), "participant.id is required", errors)
    require(
        participant.get("profile") in catalog["approved_profiles"],
        "participant.profile is not approved",
        errors,
    )
    require(
        isinstance(
            participant.get("prior_opensearch_experience"), bool
        ),
        "prior_opensearch_experience must be true or false",
        errors,
    )
    require(
        session.get("consent_confirmed") is True,
        "consent_confirmed must be true",
        errors,
    )
    for field in ("started_at", "completed_at"):
        value = session.get(field)
        try:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
        except (AttributeError, ValueError):
            errors.append(f"{field} must be an ISO 8601 timestamp")

    expected = {item["id"]: item for item in catalog["scenarios"]}
    observed = {
        item.get("id"): item for item in session.get("scenarios", [])
    }
    require(
        set(observed) == set(expected),
        "session must contain every catalog scenario exactly once",
        errors,
    )
    for scenario_id, definition in expected.items():
        result = observed.get(scenario_id, {})
        require(
            isinstance(result.get("success"), bool),
            f"{scenario_id}.success must be true or false",
            errors,
        )
        seconds = result.get("completion_seconds")
        require(
            isinstance(seconds, int) and 0 < seconds,
            f"{scenario_id}.completion_seconds must be a positive integer",
            errors,
        )
        if isinstance(seconds, int):
            require(
                seconds <= definition["time_limit_seconds"],
                f"{scenario_id} exceeded its time limit",
                errors,
            )
        assistance = result.get("assistance_count")
        require(
            isinstance(assistance, int) and assistance >= 0,
            f"{scenario_id}.assistance_count must be zero or greater",
            errors,
        )
        require(
            isinstance(result.get("server_access_used"), bool),
            f"{scenario_id}.server_access_used must be true or false",
            errors,
        )
        rating = result.get("difficulty_rating")
        require(
            isinstance(rating, int) and 1 <= rating <= 5,
            f"{scenario_id}.difficulty_rating must be from 1 to 5",
            errors,
        )
    post = session.get("post_study", {})
    confidence = post.get("confidence_rating")
    require(
        isinstance(confidence, int) and 1 <= confidence <= 5,
        "post_study.confidence_rating must be from 1 to 5",
        errors,
    )
    require(
        isinstance(post.get("would_use_without_help"), bool),
        "post_study.would_use_without_help must be true or false",
        errors,
    )
    return errors


def summarize(sessions, catalog):
    acceptance = catalog["acceptance"]
    scenario_rows = []
    server_access_uses = 0
    for definition in catalog["scenarios"]:
        results = [
            next(
                item for item in session["scenarios"]
                if item["id"] == definition["id"]
            )
            for session in sessions
        ]
        server_access_uses += sum(
            item["server_access_used"] for item in results
        )
        scenario_rows.append({
            "id": definition["id"],
            "title": definition["title"],
            "success_rate": (
                sum(item["success"] for item in results) / len(results)
            ),
            "median_seconds": statistics.median(
                item["completion_seconds"] for item in results
            ),
            "median_difficulty": statistics.median(
                item["difficulty_rating"] for item in results
            ),
            "assistance_count": sum(
                item["assistance_count"] for item in results
            ),
        })
    profiles = Counter(
        session["participant"]["profile"] for session in sessions
    )
    mean_confidence = statistics.mean(
        session["post_study"]["confidence_rating"] for session in sessions
    )
    ready = (
        len(sessions) >= catalog["minimum_participants"]
        and len(profiles) >= acceptance["minimum_profile_count"]
        and any(
            profile in profiles
            for profile in ("security-analyst", "network-analyst")
        )
        and all(
            row["success_rate"]
            >= acceptance["minimum_scenario_success_rate"]
            and row["median_difficulty"]
            <= acceptance["maximum_median_difficulty"]
            for row in scenario_rows
        )
        and server_access_uses
        <= acceptance["maximum_server_access_uses"]
        and mean_confidence >= acceptance["minimum_mean_confidence"]
    )
    return {
        "ready": ready,
        "participant_count": len(sessions),
        "profiles": dict(sorted(profiles.items())),
        "mean_confidence": mean_confidence,
        "would_use_without_help_rate": (
            sum(
                session["post_study"]["would_use_without_help"]
                for session in sessions
            )
            / len(sessions)
        ),
        "server_access_uses": server_access_uses,
        "scenarios": scenario_rows,
    }


def markdown_report(summary):
    lines = [
        "# Phase 5 usability test results",
        "",
        f"**Gate result:** {'PASS' if summary['ready'] else 'INCOMPLETE'}",
        "",
        f"- Participants: {summary['participant_count']}",
        "- Profiles: " + ", ".join(
            f"{name} ({count})"
            for name, count in summary["profiles"].items()
        ),
        f"- Mean confidence: {summary['mean_confidence']:.2f}/5",
        "- Would work without help: "
        f"{summary['would_use_without_help_rate']:.0%}",
        f"- Direct server access uses: {summary['server_access_uses']}",
        "",
        "| Scenario | Success | Median time | Median difficulty | Assistance |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for row in summary["scenarios"]:
        lines.append(
            f"| {row['title']} | {row['success_rate']:.0%} | "
            f"{row['median_seconds']:.0f}s | "
            f"{row['median_difficulty']:.1f}/5 | "
            f"{row['assistance_count']} |"
        )
    lines.extend([
        "",
        "This report contains aggregate results only. Raw participant session "
        "files remain local and are excluded from Git.",
        "",
    ])
    return "\n".join(lines)


def write_json(path, payload):
    output = json.dumps(payload, indent=2) + "\n"
    if path == "-":
        sys.stdout.write(output)
    else:
        Path(path).write_text(output, encoding="utf-8")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    commands = parser.add_subparsers(dest="command", required=True)

    create = commands.add_parser("new", help="create a blank local session")
    create.add_argument("--participant-id", required=True)
    create.add_argument("--profile", required=True)
    create.add_argument("--output", required=True)

    validate = commands.add_parser("validate", help="validate session files")
    validate.add_argument("sessions", nargs="+")

    report = commands.add_parser(
        "summarize", help="create an aggregate Markdown report"
    )
    report.add_argument("sessions", nargs="+")
    report.add_argument("--output", default="-")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    catalog = load_catalog(args.catalog)
    if args.command == "new":
        write_json(
            args.output,
            new_session(catalog, args.participant_id, args.profile),
        )
        return 0

    sessions = []
    failed = False
    for path in args.sessions:
        session = load_json(path)
        errors = validate_session(session, catalog)
        if errors:
            failed = True
            for error in errors:
                print(f"{path}: {error}", file=sys.stderr)
        else:
            sessions.append(session)
    if failed:
        return 1
    if args.command == "validate":
        print(f"Validated {len(sessions)} usability session(s).")
        return 0

    summary = summarize(sessions, catalog)
    report = markdown_report(summary)
    if args.output == "-":
        sys.stdout.write(report)
    else:
        Path(args.output).write_text(report, encoding="utf-8")
    return 0 if summary["ready"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
