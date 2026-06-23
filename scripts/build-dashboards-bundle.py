#!/usr/bin/env python3
"""Build or verify the deterministic OpenSearch Dashboards saved-object bundle."""

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config/dashboards"
DEFAULT_MANIFEST = CONFIG / "saved-objects-manifest-v1.json"


def canonical_object(item):
    return {
        "id": item["id"],
        "type": item["type"],
        "attributes": item["attributes"],
        "references": item.get("references", []),
    }


def canonical_line(item):
    return json.dumps(
        canonical_object(item),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )


def load_manifest(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def build(manifest_path):
    manifest_path = Path(manifest_path)
    manifest = load_manifest(manifest_path)
    directory = manifest_path.parent
    objects = []
    seen = set()
    for source in manifest["sources"]:
        path = directory / source
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if not line:
                continue
            item = canonical_object(json.loads(line))
            key = (item["type"], item["id"])
            if key in seen:
                raise ValueError(
                    f"duplicate saved object {key} in {source}:{line_number}"
                )
            seen.add(key)
            objects.append(item)

    expected = manifest["expected_types"]
    observed = Counter(item["type"] for item in objects)
    if dict(sorted(observed.items())) != dict(sorted(expected.items())):
        raise ValueError(
            f"saved-object counts differ: expected {expected}, "
            f"observed {dict(observed)}"
        )

    available = {(item["type"], item["id"]) for item in objects}
    for item in objects:
        for reference in item["references"]:
            target = (reference["type"], reference["id"])
            if target not in available:
                raise ValueError(
                    f"{item['type']}/{item['id']} references missing {target}"
                )

    rendered = "\n".join(canonical_line(item) for item in objects) + "\n"
    return manifest, objects, rendered


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when the tracked bundle differs from generated content",
    )
    parser.add_argument(
        "--output",
        help="override the bundle path declared by the manifest",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    manifest, objects, rendered = build(args.manifest)
    bundle = Path(args.output) if args.output else (
        Path(args.manifest).parent / manifest["bundle"]
    )
    if args.check:
        if not bundle.exists() or bundle.read_text(
            encoding="utf-8"
        ) != rendered:
            print(
                f"{bundle} is stale; run scripts/build-dashboards-bundle.py",
                file=sys.stderr,
            )
            return 1
    else:
        bundle.write_text(rendered, encoding="utf-8")
    print(
        f"Dashboards bundle: {len(objects)} objects, sha256={digest(rendered)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
