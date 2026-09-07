import copy
import csv
import hashlib
import json
import uuid

import pytest

from tools.pc_acquisition.journal import JournalRecorder, RecordKind
from tools.pc_acquisition.models import ImuSample, ReceivedSample, WheelSide
from tools.pc_gui.analysis_loader import read_recording
from tools.pc_gui.analysis_timing import prepare_windows
from tools.pc_gui.analysis_contract import build_analysis
from tools.pc_gui.analysis_export import export_analysis


def recording(tmp_path):
    sid = str(uuid.uuid4())
    writer = JournalRecorder(tmp_path, session_id=sid)
    boards = {
        s: {
            "accel_scale": 0.001 if s == "L" else 0.002,
            "gyro_scale": 0.01,
            "sample_rate_hz": 100,
        }
        for s in ("L", "R")
    }
    writer.append_metadata(
        {
            "session_id": sid,
            "topic": "original",
            "sample_rate_hz": 100,
            "boards": boards,
        }
    )
    t0 = 100_000_000_000
    targets = {"L": 1_000_000, "R": 3_000_000}
    for side in ("L", "R"):
        writer.append_json(
            RecordKind.SYNC,
            {
                "side": side,
                "slope_ns_per_us": 1000.0,
                "intercept_ns": t0 - targets[side] * 1000.0,
                "observation_count": 10,
                "residual_rms_ns": 10.0,
                "best_rtt_ns": 10000,
                "median_rtt_ns": 20000,
            },
        )
    writer.append_json(
        RecordKind.EVENT,
        {"type": "START", "pc_start_ns": t0, "target_device_us": targets},
    )
    for i in range(250):
        for side in ("L", "R"):
            sample = ImuSample(
                i, targets[side] + 20000 + i * 10000, 1000, 0, 0, 0, 0, 100
            )
            writer.submit_sample(
                ReceivedSample(
                    WheelSide(side),
                    sample,
                    t0 + i * 10000000 + (300000000 if side == "R" else 200000000),
                    i,
                    "contiguous",
                )
            )
    writer.append_json(
        RecordKind.SYNC, {"phase": "post_stop", "side": "L", "slope_ns_per_us": -100}
    )
    path = writer.finalize({"quality": "GOOD", "duration_s": 2.5})
    manifest = path.with_suffix(".summary.json")
    manifest.write_text(
        json.dumps({"topic": "renamed", "boards": {"L": {"accel_scale": 42.0}}})
    )
    return sid, path, manifest


def test_journal_uses_immutable_scales_and_prestart_clock(tmp_path):
    sid, path, manifest = recording(tmp_path)
    before = path.read_bytes()
    result = read_recording(path, manifest, path.with_suffix(".csv"), sid)
    assert result["topic"] == "renamed"
    assert result["samples"]["L"][0]["ax"] == 1.0
    assert result["samples"]["R"][0]["ax"] == 2.0
    assert result["scale_provenance"]["L"]["accel_scale"]["source"] == "journal_capture"
    _, meta = prepare_windows(result)
    assert meta["time_s"][0] == pytest.approx(0.04)
    assert meta["time_s"][-1] == pytest.approx(2.49)
    assert path.read_bytes() == before


def test_invalid_journal_is_not_replaced_with_csv_or_partial_samples(tmp_path):
    sid, path, manifest = recording(tmp_path)
    path.write_bytes(path.read_bytes()[:-2])  # Synthetic temporary journal only.
    with pytest.raises(ValueError):
        read_recording(path, manifest, path.with_suffix(".csv"), sid)


def analysis():
    t = [i * 0.05 for i in range(40)]
    return build_analysis(
        times=t,
        xy=[[x, 0.0] for x in t],
        flags=[[] for _ in t],
        signed_speed=[1.0] * 40,
        yaw=[0.0] * 40,
        yaw_rate=[0.0] * 40,
        metadata={"session_id": "../unsafe/name"},
    )


def test_export_preserves_original_and_full_resolution_with_selected_metadata(tmp_path):
    a = analysis()
    before = copy.deepcopy(a)
    original = tmp_path / "raw.waj"
    original.write_bytes(b"original recording")
    out = export_analysis(a, tmp_path, start_s=0.25, stop_s=0.75)
    rows = list(
        csv.DictReader((out / "timeline.csv").open(encoding="utf-8", newline=""))
    )
    meta = json.loads((out / "metadata.json").read_text())
    assert len(rows) == 40 and float(rows[-1]["time_s"]) == a["samples"][-1]["time_s"]
    assert rows[0]["longitudinal_accel_mps2"] == ""
    assert meta["selected_window"]["samples"] == 11
    assert (
        meta["timeline_sha256"]
        == hashlib.sha256((out / "timeline.csv").read_bytes()).hexdigest()
    )
    assert (out / "COMPLETE").is_file()
    assert original.read_bytes() == b"original recording" and a == before
    second = export_analysis(a, tmp_path)
    assert second != out and (out / "timeline.csv").is_file()


def test_export_fails_before_creating_files_for_bad_result(tmp_path):
    a = analysis()
    a["samples"][5]["x_m"] = float("nan")
    with pytest.raises(ValueError):
        export_analysis(a, tmp_path)
    assert not list(tmp_path.iterdir())
