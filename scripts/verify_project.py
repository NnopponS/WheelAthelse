"""Check current engineering docs and the publication boundary without dependencies.

Run from any working directory. --staged reads staged content, not working copies.
Private archives are deliberately excluded; no file is modified by this command.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILES = {'README.md', 'STATUS.md', 'HANDOFF.md', 'architecture.md', 'decisions.md'}
PROJECT_DIRS = {'plans', 'phases', 'history', 'reports', 'local'}
PRIVATE = ('.project/local/', '.project/evidence/', '.project-state-before-organization/', 'BiWheel3D/')
BAD_SUFFIXES = {'.waj', '.open', '.npz', '.c3d', '.apk', '.ipa', '.exe', '.zip', '.jks', '.keystore'}
TEXT_SUFFIXES = {'.md', '.json', '.py', '.dart', '.yml', '.yaml', '.toml', '.txt', '.ps1', '.bat'}
SECRET = re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{30,}\b')
LINK = re.compile(r'(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)')


def git(*args: str) -> bytes:
    result = subprocess.run(['git', '-C', str(ROOT), *args], capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace').strip())
    return result.stdout


def publication_errors(name: str, data: bytes) -> list[str]:
    errors = []
    path = PurePosixPath(name)
    if name.startswith(PRIVATE):
        errors.append(f'{name}: private/local material must not be published')
    if path.suffix.lower() in BAD_SUFFIXES:
        errors.append(f'{name}: generated, research, or signing artifact must not be published')
    if len(data) > 10 * 1024 * 1024:
        errors.append(f'{name}: new/changed files above 10 MiB require a separate artifact review')
    if path.suffix in TEXT_SUFFIXES:
        text = data.decode('utf-8-sig', errors='replace')
        if SECRET.search(text):
            errors.append(f'{name}: possible credential/private key')
    return errors


def check(staged: bool = False) -> dict:
    tracked = set(git('ls-files', '-z').decode('utf-8').split('\0')) - {''}
    added = set(git('ls-files', '--others', '--exclude-standard', '-z').decode('utf-8').split('\0')) - {''}
    names = tracked if staged else tracked | added
    if not staged:
        names = {name for name in names if (ROOT / name).is_file()}
    modified = set(git('diff', '--cached' if staged else 'HEAD', '--name-only', '--diff-filter=ACMR', '-z').decode('utf-8').split('\0')) - {''}
    if not staged:
        modified |= added

    def read(name: str) -> bytes:
        return git('show', ':' + name) if staged else (ROOT / name).read_bytes()

    errors: list[str] = []
    for name in sorted(names):
        if name.startswith(PRIVATE):
            errors.append(f'{name}: private archive or separate research repository is in the candidate tree')
        if name.startswith('.project/'):
            parts = PurePosixPath(name).parts
            if len(parts) == 2 and parts[1] not in PROJECT_FILES:
                errors.append(f'{name}: use a current canonical file or a topic subdirectory')
            elif len(parts) > 2 and parts[1] not in PROJECT_DIRS:
                errors.append(f'{name}: unknown project-state directory')
        if name in modified:
            errors.extend(publication_errors(name, read(name)))
    docs = sorted(name for name in names if name.endswith('.md') and (
        name.startswith('.project/') or name.startswith('docs/model_analysis/')))
    for name in docs:
        text = read(name).decode('utf-8-sig')
        if re.search(r'[A-Z]:[\\/]Users[\\/]', text, re.I):
            errors.append(f'{name}: private absolute user path in public engineering documentation')
        if '\ufffd' in text or '\u00e2\u20ac' in text or '\u00e2\u201d' in text:
            errors.append(f'{name}: corrupted text encoding')
        for target in LINK.findall(text):
            target = target.split(' "', 1)[0].strip('<>')
            if re.match(r'[a-z]+:', target, re.I) or target.startswith('#'):
                continue
            destination = unquote(target.split('#')[0])
            path = (ROOT / name).parent / destination
            relative = Path(path).resolve().relative_to(ROOT).as_posix()
            if staged:
                exists = relative in names or any(n.startswith(relative.rstrip('/') + '/') for n in names)
            else:
                exists = path.exists()
            if not exists:
                errors.append(f'{name}: unresolved local link {target}')
    for name in PROJECT_FILES:
        if '.project/' + name not in names:
            errors.append('Missing canonical .project/' + name)
    fixture = 'docs/model_analysis/fixtures/analysis_v1.json'
    if fixture not in names:
        errors.append('Shared analytical fixture missing from publishable tree')
    else:
        value = json.loads(read(fixture))
        if value.get('schema_version') != 1 or len(value.get('cases', [])) != 11:
            errors.append('Unexpected shared analytical fixture schema/case count')
    # Track the ignore policy itself: do not silently publish archive files on a clean clone.
    ignored = subprocess.run(['git', '-C', str(ROOT), 'check-ignore', '--quiet', '.project/local/private-session.waj'], check=False)
    if ignored.returncode != 0:
        errors.append('.project/local is not ignored by Git')
    return {'scope': 'staged' if staged else 'working-tree', 'candidate_files': len(names),
            'checked_documents': len(docs), 'checked_changed_files': len(modified),
            'errors': errors, 'passed': not errors}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true')
    args = parser.parse_args()
    try:
        result = check(args.staged)
    except (OSError, RuntimeError, ValueError) as error:
        print(f'Project verification could not complete: {error}', file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
