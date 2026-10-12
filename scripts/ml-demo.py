#!/usr/bin/env python3
"""Run advisory authentication scoring and explain the results, without Docker."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--events', type=Path, default=ROOT / 'tests/ml/fixtures/auth-shadow-evaluation.jsonl')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'runtime/demos/ml')
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    predictions = args.output_dir / 'predictions.jsonl'
    subprocess.run([sys.executable, str(ROOT / 'scripts/ml-shadow-score.py'),
                    '--events', str(args.events.resolve()),
                    '--model-metadata', str(ROOT / 'config/ml/mlflow-model-registry-entry-v1.json'),
                    '--output', str(predictions),
                    '--metrics-output', str(args.output_dir / 'metrics.json')], check=True)
    records = [json.loads(line)['prediction'] for line in predictions.read_text().splitlines() if line]
    lines = ['Authentication anomaly scoring (shadow mode)',
             'Learns normal failed-login counts from training rows; scores evaluation rows.',
             'Scores range from 0 to 1. Anomalous means review the event; no traffic is blocked.',
             'This is a statistical baseline, not a trained neural network.', '']
    for record in records:
        lines.append(f"{record['source_event_id']}: {record['classification']} "
                     f"(score {record['score']:.2f}) — " + ', '.join(record['supporting_evidence']))
    lines += ['', 'Metrics need analyst labels to measure accuracy; unlabelled rows are not accuracy evidence.',
              'Next: investigate anomalies, label outcomes, then compare against detection rules.',
              'Traffic dashboard example: python3 scripts/setup.py --demo --ml',
              'Own data instructions: docs/guides/machine-learning.md']
    summary = '\n'.join(lines) + '\n'
    (args.output_dir / 'summary.txt').write_text(summary)
    print(summary)
    print(f'Results saved to {args.output_dir}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f'ML scoring failed: {exc}', file=sys.stderr)
        sys.exit(1)
