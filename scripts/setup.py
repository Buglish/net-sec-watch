#!/usr/bin/env python3
"""Repeatable local installation with actionable checks and dashboard defaults."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def run(*args, env=None, capture=False):
    return subprocess.run(args, cwd=ROOT, env=env, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None)


def doctor():
    missing = [name for name in ('docker', 'bash', 'curl', 'openssl', 'python3')
               if not shutil.which(name)]
    if missing:
        raise ValueError('Install required tools: ' + ', '.join(missing)
                         + '. See docs/guides/getting-started.md.')
    run('docker', 'compose', 'version', capture=True)
    run('docker', 'info', capture=True)
    print('Required tools and Docker daemon are available.', flush=True)
    setting = Path('/proc/sys/vm/max_map_count')
    if setting.exists() and int(setting.read_text()) < 262144:
        raise ValueError('OpenSearch needs vm.max_map_count >= 262144. Run '
                         'sudo sysctl -w vm.max_map_count=262144 on the Docker host '
                         '(Docker Desktop: see its VM settings), then retry.')


def endpoint(config, service, target):
    port = next(p for p in config['services'][service]['ports']
                if int(p['target']) == target)
    host = port.get('host_ip', '127.0.0.1')
    if host in ('0.0.0.0', '::'):
        host = '127.0.0.1'
    if ':' in host:
        host = '[' + host + ']'
    return f"http://{host}:{port['published']}"


def wait_for(url, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            pass
        time.sleep(2)
    raise ValueError(f'Timed out waiting for {url}. Run make logs-opensearch or '
                     'make logs-dashboards; fix the reported error and rerun setup.')



def wait_for_demo(search, timeout):
    deadline = time.monotonic() + timeout
    url = search + '/net-sec-watch-network-*/_search?q=NetSecWatchDemo001'
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if json.load(response).get('hits', {}).get('hits'):
                    print('Confirmed sample syslog event reached OpenSearch.', flush=True)
                    return
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            pass
        time.sleep(2)
    raise ValueError('Services started but sample ingestion could not be confirmed. '
                     'Run make logs to check collector output, then rerun setup.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--doctor', action='store_true', help='check prerequisites only')
    parser.add_argument('--demo', action='store_true', help='also generate sample logs')
    parser.add_argument('--ml', action='store_true', help='also populate traffic ML demo')
    parser.add_argument('--timeout', type=int, default=300, help='readiness timeout in seconds')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    doctor()
    if args.doctor:
        return
    run('bash', 'scripts/init-local-config.sh')
    env = os.environ.copy()
    compose = ['docker', 'compose', '--env-file', '.env', '--profile', 'opensearch']
    config = json.loads(run(*compose, 'config', '--format', 'json', capture=True).stdout)
    active = config['services']['fluent-bit']['volumes']
    source = next(v['source'] for v in active if v['target'] == '/fluent-bit/etc/fluent-bit.conf')
    if Path(source).resolve() not in (ROOT / 'config/fluent-bit.conf', ROOT / 'config/fluent-bit.demo.conf'):
        raise ValueError('Setup uses the local HTTP stack. Your custom collector config was '
                         'preserved. Use the manual/secure guide, or set '
                         'FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.demo.conf in .env.')
    # Persist the output config so subsequent Compose restarts keep indexing logs.
    path = ROOT / '.env'
    lines = path.read_text().splitlines()
    lines = [line for line in lines if not line.startswith('FLUENT_BIT_CONFIG_PATH=')]
    path.write_text('\n'.join(lines) + '\nFLUENT_BIT_CONFIG_PATH=./config/fluent-bit.demo.conf\n')
    env['FLUENT_BIT_CONFIG_PATH'] = './config/fluent-bit.demo.conf'
    search = endpoint(config, 'opensearch', 9200)
    dashboards = endpoint(config, 'opensearch-dashboards', 5601)
    env['OPENSEARCH_ENDPOINT'] = search
    env['OPENSEARCH_DASHBOARDS_ENDPOINT'] = dashboards
    print('Starting collector, search and dashboards (first pull can take several minutes)...', flush=True)
    run(*compose, 'up', '-d', 'fluent-bit', 'opensearch', 'opensearch-dashboards', env=env)
    wait_for(search + '/_cluster/health', args.timeout)
    wait_for(dashboards + '/api/status', args.timeout)
    run('bash', 'scripts/import-dashboards.sh', env=env)
    if args.demo:
        run('bash', 'scripts/generate-sample-logs.sh', env=env)
        # The demo sender reads this override rather than assuming the default host port.
        syslog = next(p for p in config['services']['fluent-bit']['ports']
                      if p['protocol'] == 'udp')
        env['SYSLOG_TEST_PORT'] = str(syslog['published'])
        run('bash', 'scripts/send-demo-syslog.sh', env=env)
        wait_for_demo(search, args.timeout)
    if args.ml:
        run('bash', 'scripts/run-traffic-classification-demo.sh', env=env)
    print(f'\nReady: {dashboards}/app/dashboards')
    print('Open Net Sec Watch - Network; set the time picker to Last 24 hours.')
    print('Next: make ml-demo for an offline explanation; make down to stop without deleting data.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Setup failed: {exc}', file=sys.stderr)
        sys.exit(1)
