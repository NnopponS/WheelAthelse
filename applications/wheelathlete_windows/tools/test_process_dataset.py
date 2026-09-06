import unittest
import json
import tempfile
from pathlib import Path

import numpy as np

from process_dataset import (
    align_envelopes,
    detect_three_pulse_cue,
    normalize_label,
    robust_sequence_fit,
    validate_generated_output,
)


class DatasetProcessorTests(unittest.TestCase):
    def test_normalizes_legacy_slalop_label(self):
        self.assertEqual(normalize_label("slalop"), "slalom")

    def test_sequence_fit_rejects_arrival_outlier(self):
        seq = np.arange(100, dtype=np.int64)
        arrival = 1000.0 + seq * 10.0
        arrival[50] += 1000.0
        _, slope, rms = robust_sequence_fit(seq, arrival)
        self.assertAlmostEqual(slope, 10.0, places=3)
        self.assertLess(rms, 0.01)

    def test_alignment_recovers_known_offset_and_small_drift(self):
        x = np.linspace(0, 20, 2000)
        imu = np.sin(x) + 0.5 * np.sin(3.7 * x) + (np.arange(2000) % 173 == 0) * 3
        scale = 1.001
        stretched = np.interp(
            np.linspace(0, len(imu) - 1, round(len(imu) * scale)),
            np.arange(len(imu)),
            imu,
        )
        c3d = np.r_[np.zeros(37), stretched, np.zeros(20)]
        result = align_envelopes(imu, c3d)
        self.assertLessEqual(abs(result.lag_frames - 37), 1)
        self.assertLessEqual(abs(result.drift_ppm - 1000), 600)
        self.assertGreater(result.correlation, 0.9)

    def test_detects_three_pulse_cue_with_quiet_periods(self):
        envelope = np.zeros(800)
        envelope[[200, 300, 400]] = 10
        envelope = np.convolve(envelope, np.ones(15), mode="same")
        cue = detect_three_pulse_cue(envelope)
        self.assertIsNotNone(cue)
        self.assertLessEqual(abs(cue - 300), 2)

    def test_validation_report_excludes_its_own_unstable_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("raw", "training", "qc"):
                (root / name).mkdir()
            (root / "raw" / "left.csv").write_text(
                "time_us,ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps\n"
                "0,0,0,0,0,0,0\n",
                encoding="utf-8",
            )
            (root / "training" / "trial.csv").write_text(
                "time_us,left_ax_g,left_ay_g,left_az_g,left_gx_dps,"
                "left_gy_dps,left_gz_dps,right_ax_g,right_ay_g,right_az_g,"
                "right_gx_dps,right_gy_dps,right_gz_dps\n"
                "0,0,0,0,0,0,0,0,0,0,0,0,0\n",
                encoding="utf-8",
            )
            (root / "qc" / "trial.json").write_text("{}", encoding="utf-8")
            (root / "dataset_manifest.csv").write_text(
                "status,ready_to_train\nready,True\n",
                encoding="utf-8",
            )

            first = validate_generated_output(root)
            second = validate_generated_output(root)

            self.assertEqual(first["checked_file_count"], 4)
            self.assertEqual(second["checked_file_count"], 4)
            report = json.loads(
                (root / "qc" / "validation_report.json").read_text(encoding="utf-8")
            )
            self.assertNotIn(
                "qc/validation_report.json",
                {entry["file"].replace("\\", "/") for entry in report["files"]},
            )


if __name__ == "__main__":
    unittest.main()
