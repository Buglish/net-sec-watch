#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "usability_study", ROOT / "scripts/usability-study.py"
)
STUDY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STUDY)


class UsabilityStudyTest(unittest.TestCase):
    def setUp(self):
        self.catalog = STUDY.load_catalog()

    def complete_session(self, participant_id, profile, confidence=5):
        session = STUDY.new_session(
            self.catalog, participant_id, profile
        )
        session["participant"]["prior_opensearch_experience"] = False
        session["consent_confirmed"] = True
        now = datetime.now(timezone.utc).isoformat()
        session["started_at"] = now
        session["completed_at"] = now
        for scenario in session["scenarios"]:
            scenario.update({
                "success": True,
                "completion_seconds": 180,
                "assistance_count": 0,
                "server_access_used": False,
                "difficulty_rating": 2,
            })
        session["post_study"].update({
            "confidence_rating": confidence,
            "would_use_without_help": True,
        })
        return session

    def test_new_session_covers_versioned_scenarios(self):
        session = STUDY.new_session(
            self.catalog, "P01", "security-analyst"
        )
        self.assertEqual(
            [item["id"] for item in session["scenarios"]],
            [item["id"] for item in self.catalog["scenarios"]],
        )
        self.assertFalse(session["consent_confirmed"])

    def test_validation_rejects_incomplete_or_serverless_claims(self):
        session = self.complete_session("P01", "security-analyst")
        self.assertEqual(STUDY.validate_session(session, self.catalog), [])
        broken = deepcopy(session)
        broken["scenarios"][0]["completion_seconds"] = None
        self.assertTrue(STUDY.validate_session(broken, self.catalog))

    def test_summary_passes_only_with_target_user_thresholds(self):
        sessions = [
            self.complete_session("P01", "security-analyst"),
            self.complete_session("P02", "network-analyst"),
            self.complete_session("P03", "operations-engineer"),
        ]
        summary = STUDY.summarize(sessions, self.catalog)
        self.assertTrue(summary["ready"])
        self.assertIn("**Gate result:** PASS", STUDY.markdown_report(summary))

        sessions[0]["scenarios"][0]["server_access_used"] = True
        self.assertFalse(STUDY.summarize(sessions, self.catalog)["ready"])

    def test_documentation_covers_catalog_and_commands(self):
        plan = (
            ROOT / "docs/phase-5-usability-test-plan.md"
        ).read_text(encoding="utf-8")
        for scenario in self.catalog["scenarios"]:
            self.assertIn(f"`{scenario['id']}`", plan)
        for command in (
            "usability-study.py new",
            "usability-study.py validate",
            "usability-study.py summarize",
        ):
            self.assertIn(command, plan)


if __name__ == "__main__":
    unittest.main()
