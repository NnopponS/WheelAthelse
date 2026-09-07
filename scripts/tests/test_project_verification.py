import importlib.util
import json
import subprocess
import tempfile
from unittest.mock import patch
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('verify_project', ROOT / 'scripts/verify_project.py')
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicationBoundaryTests(unittest.TestCase):
    def test_private_evidence_is_rejected(self):
        for path in ['.project/local/session.json', '.project/evidence/private.txt', 'BiWheel3D/source.py']:
            with self.subTest(path=path):
                self.assertTrue(module.publication_errors(path, b'{}'))

    def test_generated_and_signing_files_are_rejected(self):
        for suffix in ['.waj', '.npz', '.c3d', '.apk', '.exe', '.zip', '.jks', '.keystore']:
            with self.subTest(suffix=suffix):
                self.assertTrue(module.publication_errors('docs/output' + suffix, b'example'))

    def test_oversized_new_artifact_is_rejected(self):
        self.assertTrue(module.publication_errors('docs/large.dat', b'0' * (10 * 1024 * 1024 + 1)))

    def test_source_and_synthetic_fixture_are_allowed(self):
        self.assertFalse(module.publication_errors('scripts/example.py', b'print(1)'))
        self.assertFalse(module.publication_errors('docs/model_analysis/fixtures/example.json', b'{"synthetic": true}'))

    def test_secret_key_header_is_rejected(self):
        sample = b'-----BEGIN ' + b'PRIVATE KEY-----'
        self.assertTrue(module.publication_errors('scripts/config.txt', sample))

    def test_placeholder_is_not_a_secret(self):
        self.assertFalse(module.publication_errors('docs/setup.md', b'Use an externally provided signing key.'))


class PublicationSnapshotTests(unittest.TestCase):
    """Exercise actual Git trees, including the clean checkout used by CI."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Publication Test')
        self.git('config', 'user.email', 'publication-test@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        self.write('.gitignore', '.project/local/\n')
        for name in module.PROJECT_FILES:
            self.write('.project/' + name, '# Synthetic project document\n')
        self.write('docs/model_analysis/fixtures/analysis_v1.json',
                   json.dumps({'schema_version': 1, 'cases': [{} for _ in range(11)]}))
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Synthetic baseline')
        root_patch = patch.object(module, 'ROOT', self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args],
                              check=True, capture_output=True).stdout

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode('utf-8'))

    def commit_file(self, name, content):
        self.write(name, content)
        self.git('add', '--', name)
        self.git('commit', '--quiet', '-m', 'Synthetic case')

    def test_clean_candidate_tree_passes(self):
        for staged in (False, True):
            with self.subTest(staged=staged):
                self.assertTrue(module.check(staged)['passed'])

    def test_clean_checkout_rejects_committed_key_header(self):
        self.commit_file('docs/config.txt', b'-----BEGIN ' + b'PRIVATE KEY-----')
        for staged in (False, True):
            with self.subTest(staged=staged):
                result = module.check(staged)
                self.assertFalse(result['passed'])
                self.assertTrue(any('possible credential' in error for error in result['errors']))

    def test_clean_checkout_rejects_committed_empty_artifact(self):
        self.commit_file('docs/capture.c3d', b'')
        for staged in (False, True):
            with self.subTest(staged=staged):
                result = module.check(staged)
                self.assertFalse(result['passed'])
                self.assertTrue(any('docs/capture.c3d:' in error for error in result['errors']))

    def test_staged_view_does_not_read_unstaged_repair(self):
        self.commit_file('docs/config.txt', b'-----BEGIN ' + b'PRIVATE KEY-----')
        self.write('docs/config.txt', 'No credentials here.')
        self.assertTrue(module.check(False)['passed'])
        self.assertFalse(module.check(True)['passed'])

    def test_staged_view_ignores_unstaged_changes(self):
        self.commit_file('docs/config.txt', 'No credentials here.')
        self.write('docs/config.txt', b'-----BEGIN ' + b'PRIVATE KEY-----')
        self.assertFalse(module.check(False)['passed'])
        self.assertTrue(module.check(True)['passed'])

    def test_staged_view_ignores_untracked_artifact(self):
        self.write('docs/capture.c3d', b'')
        self.assertFalse(module.check(False)['passed'])
        self.assertTrue(module.check(True)['passed'])

    def test_staged_deletion_removes_artifact_from_candidate_tree(self):
        self.commit_file('docs/capture.c3d', b'synthetic')
        self.git('rm', '--', 'docs/capture.c3d')
        self.assertTrue(module.check(False)['passed'])
        self.assertTrue(module.check(True)['passed'])

    def test_uppercase_text_suffix_cannot_bypass_credential_check(self):
        self.assertTrue(module.publication_errors('docs/config.TXT',
                        b'-----BEGIN ' + b'PRIVATE KEY-----'))


if __name__ == '__main__':
    unittest.main()
