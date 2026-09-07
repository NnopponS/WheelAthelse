import importlib.util
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


if __name__ == '__main__':
    unittest.main()
