import copy
import json
from pathlib import Path

import numpy as np
import pytest

from tools.pc_gui.analysis_contract import (
    build_analysis,
    derivative,
    nearest_index,
    validate_analysis,
    window_statistics,
)
from tools.pc_gui.analysis_timing import AnalysisInputError, prepare_windows
from tools.pc_gui.model_inference import (
    CURRENT_BEST_RECIPE_NAME,
    ModelSpec,
    run_session_model,
)


def session(n=500, offset=0.0):
    def rows(sign):
        return [
            dict(
                t=offset + i / 100,
                seq=i,
                ax=1.0,
                ay=0.0,
                az=0.0,
                gx=0.0,
                gy=0.0,
                gz=sign * 180.0,
            )
            for i in range(n)
        ]

    return dict(
        session_id="fixture", sample_rate_hz=100, samples={"L": rows(1), "R": rows(-1)}
    )


def test_offset_and_last_complete_window_are_not_lost():
    s = session(503, 4.2)
    w, m = prepare_windows(s)
    assert w.shape == (100, 5, 12)
    assert m["time_s"][0] == pytest.approx(4.22)
    assert m["time_s"][-1] == pytest.approx(9.17)
    assert m["discarded_tail_samples"] == 3
    assert "Legacy timing" in " ".join(m["warnings"])


def test_small_gap_is_flagged_but_large_gap_fails():
    s = session()
    del s["samples"]["L"][100]
    _, m = prepare_windows(s)
    assert any("small_gap_interpolated" in f for f in m["quality_flags"])
    s = session()
    del s["samples"]["L"][100:110]
    with pytest.raises(AnalysisInputError, match="gap exceeding"):
        prepare_windows(s)


@pytest.mark.parametrize(
    "kind",
    [
        "nan",
        "infinity",
        "missing_axis",
        "bad_sequence",
        "fractional_sequence",
        "partial_sequence",
        "clock_reset",
        "duplicate_conflict",
        "rate",
        "side_rate",
    ],
)
def test_malformed_inputs_fail_closed(kind):
    s = session()
    row = s["samples"]["L"][100]
    if kind == "nan":
        row["ax"] = float("nan")
    if kind == "infinity":
        row["t"] = float("inf")
    if kind == "missing_axis":
        del row["gz"]
    if kind == "bad_sequence":
        row["seq"] = -1
    if kind == "fractional_sequence":
        row["seq"] = 1.5
    if kind == "partial_sequence":
        del row["seq"]
    if kind == "duplicate_conflict":
        row["seq"] = 99
        row["gz"] = 42.0
    if kind == "clock_reset":
        for i, r in enumerate(s["samples"]["L"]):
            r["t_device_us"] = (i if i < 100 else i - 100) * 10000
    if kind == "rate":
        s["sample_rate_hz"] = 0
    if kind == "side_rate":
        s["analysis_timing"] = {"side_sample_rates": {"L": 100, "R": 200}}
    with pytest.raises(AnalysisInputError):
        prepare_windows(s)


def test_identical_replay_and_out_of_order_preserve_all_unique_samples():
    s = session()
    expected, _ = prepare_windows(s)
    row = s["samples"]["L"].pop(40)
    s["samples"]["L"].insert(43, row)
    duplicate = dict(s["samples"]["L"][100], t=7.0)
    s["samples"]["L"].append(duplicate)
    actual, meta = prepare_windows(s)
    np.testing.assert_array_equal(actual, expected)
    assert meta["side_diagnostics"]["L"]["duplicates"] == 1
    assert meta["side_diagnostics"]["L"]["reordered"] >= 1


def test_sequence_rollover_is_preserved():
    s = session()
    for side in ("L", "R"):
        for i, row in enumerate(s["samples"][side]):
            row["seq"] = (2**32 - 200 + i) % 2**32
    w, m = prepare_windows(s)
    assert w.shape[0] == 100
    assert m["side_diagnostics"]["L"]["rollovers"] == 1


def mapped_session(rollover=False):
    s = session()
    t0 = 9_000_000_000_000
    targets = {"L": 2**32 - 80000 if rollover else 1000000, "R": 3000000}
    models = {}
    for side in ("L", "R"):
        target = targets[side]
        models[side] = dict(
            slope_ns_per_us=1000.0,
            intercept_ns=t0 - target * 1000.0,
            observation_count=10,
            residual_rms_ns=20.0,
            best_rtt_ns=10000,
            median_rtt_ns=20000,
        )
        for i, row in enumerate(s["samples"][side]):
            row["t_device_us"] = (target + 100000 + i * 10000) % 2**32
            row["t"] += 2.0 if side == "L" else 3.0
    s["analysis_timing"] = dict(
        clock_models=models, start=dict(pc_start_ns=t0, target_device_us=targets)
    )
    return s


@pytest.mark.parametrize("rollover", [False, True])
def test_saved_affine_uses_common_recording_start_not_arrival(rollover):
    _, m = prepare_windows(mapped_session(rollover))
    assert m["time_basis"] == "saved_device_affine"
    assert m["time_s"][0] == pytest.approx(0.12)
    assert m["time_s"][-1] == pytest.approx(5.07)
    assert not m["physical_sync_verified"]


@pytest.mark.parametrize("bad", ["slope", "target", "partial", "nan_residual"])
def test_incompatible_saved_clock_is_not_silently_relabelled(bad):
    s = mapped_session()
    if bad == "slope":
        s["analysis_timing"]["clock_models"]["L"]["slope_ns_per_us"] = -10
    if bad == "target":
        s["analysis_timing"]["start"]["target_device_us"]["L"] += 1000
    if bad == "partial":
        del s["analysis_timing"]["clock_models"]["R"]
    if bad == "nan_residual":
        s["analysis_timing"]["clock_models"]["R"]["residual_rms_ns"] = float("nan")
    with pytest.raises(AnalysisInputError):
        prepare_windows(s)


def test_irregular_declared_times_are_used_without_nominal_replacement():
    s = session()
    s["analysis_timing"] = {"basis": "declared_recording_relative"}
    for side in ("L", "R"):
        for i, row in enumerate(s["samples"][side]):
            row["t"] = 3 + i * 0.01002
            row["ax"] = row["t"]
    w, m = prepare_windows(s)
    assert m["time_s"][0] == pytest.approx(3.02)
    assert float(w[1, 0, 0]) / 9.80665 == pytest.approx(3.05, rel=1e-6)


def fixture(v=-2.0, rate=0.0, n=50):
    t = [3.02 + i * 0.05 for i in range(n)]
    xy = [[v * (x - t[0]), 0.0] for x in t]
    return build_analysis(
        times=t,
        xy=xy,
        flags=[[] for _ in t],
        signed_speed=[v] * n,
        yaw=[rate * (x - t[0]) for x in t],
        yaw_rate=[rate] * n,
    )


def test_reverse_speed_is_signed_and_acceleration_edges_are_null():
    a = fixture()
    assert all(
        p["signed_speed_mps"] == -2.0 and p["speed_mps"] == 2.0 for p in a["samples"]
    )
    assert all(
        p["longitudinal_accel_mps2"] is None
        for p in a["samples"][:3] + a["samples"][-3:]
    )
    assert all(p["longitudinal_accel_mps2"] == 0.0 for p in a["samples"][3:-3])
    assert json.loads(json.dumps(a, allow_nan=False)) == a


def test_pivot_retains_unwrapped_yaw_despite_no_translation():
    a = fixture(v=0.0, rate=8.0)
    assert a["samples"][-1]["yaw_rad"] > 4 * np.pi
    st = window_statistics(a, a["samples"][4]["time_s"], a["samples"][40]["time_s"])
    assert st["path_length_m"] == 0
    assert st["net_yaw_rad"] == pytest.approx(8.0 * 36 * 0.05)
    assert a["samples"][4]["yaw_rad"] != 0


def test_xy_only_never_fabricates_chair_heading_or_longitudinal_acceleration():
    t = [i * 0.05 for i in range(50)]
    a = build_analysis(times=t, xy=[[0.0, 0.0] for _ in t], flags=[[] for _ in t])
    assert all(
        p["yaw_rad"] is None
        and p["yaw_rate_radps"] is None
        and p["signed_speed_mps"] is None
        and p["longitudinal_accel_mps2"] is None
        for p in a["samples"]
    )
    assert a["samples"][20]["speed_mps"] == 0.0


def test_derivative_uses_actual_times_and_invalidates_gap_halo():
    t = [i * 0.05 + (0.001 if i % 2 else 0) for i in range(30)]
    v = [2 * x + 4 for x in t]
    bad = [False] * 30
    bad[15] = True
    d = derivative(t, v, bad)
    assert all(x == pytest.approx(2.0) for x in d[3:12])
    assert all(x is None for x in d[12:19])


@pytest.mark.parametrize(
    "kind", ["nan", "backwards_time", "bad_magnitude", "missing", "metadata_nan"]
)
def test_contract_rejects_malformed_serialization(kind):
    a = fixture()
    if kind == "nan":
        a["samples"][5]["yaw_rad"] = float("nan")
    if kind == "backwards_time":
        a["samples"][5]["time_s"] = 0
    if kind == "bad_magnitude":
        a["samples"][5]["speed_mps"] = -1
    if kind == "missing":
        del a["samples"][5]["yaw_rate_radps"]
    if kind == "metadata_nan":
        a["metadata"]["bad"] = float("nan")
    with pytest.raises(ValueError):
        validate_analysis(a)


def test_cursor_tie_and_inclusive_window():
    a = fixture()
    ts = [p["time_s"] for p in a["samples"]]
    assert nearest_index(ts, (ts[3] + ts[4]) / 2) == 3
    assert nearest_index(ts, -100.0) == 0
    assert nearest_index(ts, 100.0) == len(ts) - 1
    assert window_statistics(a, ts[4], ts[8])["samples"] == 5
    assert window_statistics(a, 0.0, 1.0)["samples"] == 0


def test_real_recipe_exposes_all_kinematics_and_applied_zero_delay():
    root = Path(__file__).resolve().parents[1]
    recipe = root / "biwheel3d_runtime" / CURRENT_BEST_RECIPE_NAME
    spec = ModelSpec("fixture", "Frozen recipe", recipe, "test")
    result = run_session_model(root, spec, session())
    a = result["analysis"]
    assert len(a["samples"]) == result["point_count"] == 100
    assert (
        result["yaw_delay_frames"] == 0
    )  # Low-yaw bypass is zero, not truthy fallback 27.
    assert a["metadata"]["applied_yaw_delay_frames"] == 0
    assert all(p["yaw_rad"] is not None for p in a["samples"])
    assert a["metadata"]["xy_frame"] == "first_travel_display"
    assert a["metadata"]["yaw_frame"] == "initial_chair_heading"


def test_inputs_not_modified():
    s = mapped_session()
    before = copy.deepcopy(s)
    prepare_windows(s)
    assert s == before
