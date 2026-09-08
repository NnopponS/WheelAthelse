"""Create/check a frozen synthetic cross-language feature regression fixture.

No recordings or private fixtures are read. Expected features freeze the current
Windows implementation; this is regression/parity evidence, not physical truth.
Requires the existing Windows model requirements (NumPy).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs/model_analysis/fixtures/features_v1.json'
SEED = 20260908


def fixture_text() -> str:
    import numpy as np

    sys.path.insert(0, str(ROOT / 'applications/wheelathlete_windows'))
    from tools.pc_gui.model_inference import extract_biwheel3d_features

    # The seed and algorithm fully specify the synthetic inputs. Never load a
    # journal, C3D file, cached athlete array or the old ignored local fixture.
    windows = np.random.Generator(np.random.PCG64(SEED)).standard_normal(
        (40, 5, 12)).astype(np.float32)
    features = extract_biwheel3d_features(windows)
    source = ROOT / 'applications/wheelathlete_windows/tools/pc_gui/model_inference.py'
    provenance = {
        'kind': 'synthetic', 'seed': SEED, 'rng': 'NumPy PCG64 standard_normal',
        'generator': 'scripts/generate_feature_fixture.py',
        'input_shape': [40, 5, 12], 'feature_shape': [40, 90],
        'dtype': 'float32', 'recordings_used': False,
        'reference': 'frozen Windows protocol-v10b implementation; not C3D ground truth',
        'reference_source_sha256': hashlib.sha256(
            source.read_text(encoding='utf-8').encode('utf-8')).hexdigest(),
    }
    compact = lambda value: json.dumps(value, separators=(',', ':'), allow_nan=False)
    lines = ['{', '  "schema_version":1,',
             '  "provenance":' + compact(provenance) + ',', '  "windows":[']
    lines.extend('    ' + compact(row) + (',' if i < 39 else '')
                 for i, row in enumerate(windows.tolist()))
    lines.extend(['  ],', '  "features":['])
    lines.extend('    ' + compact(row) + (',' if i < 39 else '')
                 for i, row in enumerate(features.tolist()))
    lines.extend(['  ]', '}'])
    return '\n'.join(lines) + '\n'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true',
                        help='verify the committed fixture without modifying it')
    args = parser.parse_args()
    expected = fixture_text()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding='utf-8') != expected:
            print('Synthetic feature fixture differs from the frozen reference.', file=sys.stderr)
            return 1
        print('Synthetic feature fixture reproduces exactly.')
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # Create-only: regenerating an existing golden reference requires a reviewed edit.
    with OUTPUT.open('x', encoding='utf-8', newline='\n') as handle:
        handle.write(expected)
    print('Created ' + OUTPUT.relative_to(ROOT).as_posix())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
