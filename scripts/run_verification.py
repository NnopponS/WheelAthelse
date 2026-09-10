"""Run reproducible local/CI checks, retaining logs outside the publication tree.

No installation, device operation or publication. Each call creates a fresh run
folder and returns nonzero if any check fails, a tool is missing, or time expires.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = ROOT / 'applications/wheelathlete_windows'
MOBILE = ROOT / 'applications/wheelathlete_mobile'


def command_sets(suite: str) -> list[tuple[str, Path, list[str]]]:
    commands = []
    if suite in ('all', 'project'):
        commands.extend([
            ('project_hygiene', ROOT, [sys.executable, 'scripts/verify_project.py']),
            ('tooling_tests', ROOT, [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/tests', '-v']),
            ('update_manifest_tests', ROOT, [sys.executable, '-m', 'unittest', 'release.test_generate_update_manifest']),
        ])
    if suite in ('all', 'windows'):
        commands.append(('windows_tests', WINDOWS, [sys.executable, '-m', 'pytest',
                         'tools/pc_gui/tests', 'tools/pc_acquisition/tests', '-q']))
    if suite in ('all', 'mobile'):
        flutter = shutil.which('flutter')
        if flutter is None:
            raise FileNotFoundError('Flutter is not on PATH; no installation was attempted')
        commands.extend([
            ('flutter_analyze', MOBILE, [flutter, '--no-version-check', 'analyze', '--no-pub']),
            ('flutter_tests', MOBILE, [flutter, '--no-version-check', 'test', '--no-pub']),
        ])
    if suite == 'research':
        if not (ROOT / 'BiWheel3D/pyproject.toml').is_file():
            raise FileNotFoundError('Optional separate BiWheel3D working repository is absent')
        commands.append(('research_tests', ROOT / 'BiWheel3D', [sys.executable, '-m', 'pytest', '-q']))
    return commands


def run(suite: str, timeout: int) -> tuple[Path, dict]:
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    folder = ROOT / '.project/local/verification' / (stamp + '_' + suite)
    folder.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, PYTHONIOENCODING='utf-8', QT_QPA_PLATFORM='offscreen',
               CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    results = []
    try:
        commands = command_sets(suite)
    except (OSError, ValueError) as error:
        commands = []
        results.append({'check': 'environment', 'exit_code': 2, 'error': str(error)})
    for name, cwd, command in commands:
        log = folder / (name + '.txt')
        start = time.perf_counter()
        print('Running ' + name, flush=True)
        with log.open('x', encoding='utf-8') as stream:
            stream.write('Working directory: ' + cwd.relative_to(ROOT).as_posix() + '\n')
            stream.write('Command: ' + json.dumps(command) + '\n')
            stream.flush()
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                if os.name == 'nt':
                    subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'],
                                   stdout=stream, stderr=subprocess.STDOUT, timeout=15, check=False)
                else:
                    process.kill()
                process.wait(timeout=15)
                code = 124
            elapsed = round(time.perf_counter() - start, 3)
            stream.write(f'\nEXIT: {code}\nSECONDS: {elapsed}\n')
        results.append({'check': name, 'exit_code': code, 'seconds': elapsed,
                        'log': log.relative_to(ROOT).as_posix(),
                        'sha256': hashlib.sha256(log.read_bytes()).hexdigest()})
        print(f'{name}: exit {code} ({elapsed:.3f}s)', flush=True)
        if code:
            print(log.read_text(encoding='utf-8')[-6000:], flush=True)
    summary = {'schema_version': 1, 'at_utc': stamp, 'suite': suite,
               'checks': results, 'passed': bool(results) and all(r['exit_code'] == 0 for r in results)}
    (folder / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    return folder, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('all', 'project', 'windows', 'mobile', 'research'), default='all')
    parser.add_argument('--timeout', type=int, default=300, help='Maximum seconds per check')
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    folder, summary = run(args.suite, args.timeout)
    print(json.dumps({'folder': folder.relative_to(ROOT).as_posix(), **summary}, indent=2))
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
