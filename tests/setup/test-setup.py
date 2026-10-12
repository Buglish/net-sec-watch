#!/usr/bin/env python3
"""Regression checks for port discovery, readiness failures and ML inputs."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('setup', ROOT / 'scripts/setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def test_custom_ports_and_wildcard_bind(self):
        config = {'services': {'dashboards': {'ports': [
            {'target': 5601, 'published': '15601', 'host_ip': '0.0.0.0'}]}}}
        self.assertEqual(setup.endpoint(config, 'dashboards', 5601), 'http://127.0.0.1:15601')
        config['services']['dashboards']['ports'][0]['host_ip'] = '::1'
        self.assertEqual(setup.endpoint(config, 'dashboards', 5601), 'http://[::1]:15601')

    def test_readiness_timeout_has_recovery_instructions(self):
        with patch.object(setup.time, 'monotonic', side_effect=[0, 0, 2]), \
                patch.object(setup.time, 'sleep'), \
                patch.object(setup.urllib.request, 'urlopen', side_effect=urllib.error.URLError('offline')):
            with self.assertRaisesRegex(ValueError, 'make logs-opensearch'):
                setup.wait_for('http://localhost:9200', 1)

    def test_connection_reset_during_startup_is_retried(self):
        from io import BytesIO
        response = BytesIO(b'{}')
        response.status = 200
        with patch.object(setup.time, 'monotonic', side_effect=[0, 0, 1]), \
                patch.object(setup.time, 'sleep'), \
                patch.object(setup.urllib.request, 'urlopen',
                             side_effect=[ConnectionResetError('starting'), response]) as request:
            setup.wait_for('http://localhost:5601', 5)
            self.assertEqual(request.call_count, 2)

    def score(self, rows, directory):
        events = Path(directory) / 'events.jsonl'
        events.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')
        return subprocess.run([sys.executable, str(ROOT / 'scripts/ml-demo.py'),
                               '--events', str(events), '--output-dir', directory],
                              capture_output=True, text=True)

    def test_own_minimal_data_scores_without_extra_features(self):
        rows = [{'event.id': str(n), 'split': split,
                 'features': {'failed_login_count_10m': count}}
                for n, (split, count) in enumerate([
                    ('training', 0), ('training', 1), ('training', 2), ('evaluation', 12)])]
        with tempfile.TemporaryDirectory() as directory:
            result = self.score(rows, directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('anomalous', result.stdout)
            self.assertTrue((Path(directory) / 'summary.txt').is_file())

    def test_missing_baseline_is_actionable(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.score([{'event.id': 'new', 'split': 'evaluation',
                                  'features': {'failed_login_count_10m': 12}}], directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Include both training rows', result.stderr)

    def test_negative_counts_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.score([{'event.id': 'bad', 'split': 'training',
                                  'features': {'failed_login_count_10m': -1}}], directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('non-negative integer', result.stderr)


if __name__ == '__main__':
    unittest.main()
