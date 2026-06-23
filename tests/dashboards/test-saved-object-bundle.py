#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


BUILD = module(
    "build_dashboards_bundle",
    ROOT / "scripts/build-dashboards-bundle.py",
)
COMPARE = module(
    "compare_dashboards_export",
    ROOT / "scripts/compare-dashboards-export.py",
)


class SavedObjectBundleTest(unittest.TestCase):
    def test_tracked_bundle_is_deterministic_and_complete(self):
        manifest, objects, rendered = BUILD.build(BUILD.DEFAULT_MANIFEST)
        tracked = (
            BUILD.DEFAULT_MANIFEST.parent / manifest["bundle"]
        ).read_text(encoding="utf-8")
        self.assertEqual(tracked, rendered)
        self.assertEqual(len(objects), 13)
        self.assertEqual(len({
            (item["type"], item["id"]) for item in objects
        }), 13)

    def test_every_reference_is_inside_bundle(self):
        _, objects, _ = BUILD.build(BUILD.DEFAULT_MANIFEST)
        available = {(item["type"], item["id"]) for item in objects}
        for item in objects:
            for reference in item["references"]:
                self.assertIn(
                    (reference["type"], reference["id"]), available
                )

    def test_export_comparison_ignores_metadata_and_export_details(self):
        _, objects, _ = BUILD.build(BUILD.DEFAULT_MANIFEST)
        with tempfile.TemporaryDirectory() as directory:
            exported = Path(directory) / "export.ndjson"
            lines = []
            for item in reversed(objects):
                value = dict(item)
                value["updated_at"] = "2026-06-23T00:00:00.000Z"
                value["version"] = "ignored"
                lines.append(json.dumps(value))
            lines.append(json.dumps({
                "exportedCount": len(objects),
                "missingRefCount": 0,
            }))
            exported.write_text("\n".join(lines) + "\n", encoding="utf-8")
            self.assertEqual(
                COMPARE.compare(
                    ROOT
                    / "config/dashboards/managed-saved-objects-v1.ndjson",
                    exported,
                ),
                ([], [], []),
            )


if __name__ == "__main__":
    unittest.main()
