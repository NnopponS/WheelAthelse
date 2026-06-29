#!/usr/bin/env python3
"""WheelAthlete session CSV validator.

Usage:
    python tools/check_session.py <path/to/session_*.csv> [--meta <meta.json>] [--no-plot]

Checks:
  1. CSV schema (columns match architecture.md §3)
  2. Effective sample rate (±5% of expected)
  3. Packet loss / seq gaps
  4. Marker diff between L and R wheels (sync verification)
  5. Plots accel/gyro for both wheels on timestamp_synced_ms

Exit codes:
  0 = all checks passed
  1 = one or more checks failed
  2 = file unreadable / schema error
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import NamedTuple


# ── Data structures ────────────────────────────────────────────────────────

EXPECTED_COLUMNS = [
    "seq",
    "wheel",
    "timestamp_app_ms",
    "timestamp_device_us",
    "timestamp_synced_ms",
    "ax",
    "ay",
    "az",
    "gx",
    "gy",
    "gz",
    "marker",
]


class Sample(NamedTuple):
    seq: int
    wheel: str
    timestamp_app_ms: int
    timestamp_device_us: int
    timestamp_synced_ms: float
    ax: float
    ay: float
    az: float
    gx: float
    gy: float
    gz: float
    marker: int


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""


@dataclass
class SessionReport:
    csv_path: str
    total_samples: int = 0
    left_samples: int = 0
    right_samples: int = 0
    markers: list[Sample] = field(default_factory=list)
    left_markers: list[Sample] = field(default_factory=list)
    right_markers: list[Sample] = field(default_factory=list)
    left_seq_gaps: list[tuple[int, int]] = field(default_factory=list)
    right_seq_gaps: list[tuple[int, int]] = field(default_factory=list)
    left_effective_rate: float = 0.0
    right_effective_rate: float = 0.0
    marker_diffs_ms: list[float] = field(default_factory=list)
    results: list[CheckResult] = field(default_factory=list)

    @property
    def all_passed(self) -> bool:
        return all(r.passed for r in self.results)


# ── CSV parsing ────────────────────────────────────────────────────────────


def parse_csv(path: Path) -> tuple[list[Sample], CheckResult | None]:
    """Parse a WheelAthlete session CSV. Returns (samples, schema_error)."""
    try:
        with path.open("r", newline="") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames is None:
                return [], CheckResult("schema", False, "Empty file")
            if list(reader.fieldnames) != EXPECTED_COLUMNS:
                return [], CheckResult(
                    "schema",
                    False,
                    f"Expected {EXPECTED_COLUMNS}, got {reader.fieldnames}",
                )
            samples = []
            for i, row in enumerate(reader, start=2):
                try:
                    samples.append(
                        Sample(
                            seq=int(row["seq"]),
                            wheel=row["wheel"],
                            timestamp_app_ms=int(row["timestamp_app_ms"]),
                            timestamp_device_us=int(row["timestamp_device_us"]),
                            timestamp_synced_ms=float(row["timestamp_synced_ms"]),
                            ax=float(row["ax"]),
                            ay=float(row["ay"]),
                            az=float(row["az"]),
                            gx=float(row["gx"]),
                            gy=float(row["gy"]),
                            gz=float(row["gz"]),
                            marker=int(row["marker"]),
                        )
                    )
                except (ValueError, KeyError) as e:
                    return [], CheckResult(
                        "schema", False, f"Row {i}: parse error: {e}"
                    )
            return samples, None
    except FileNotFoundError:
        return [], CheckResult("file", False, f"File not found: {path}")
    except Exception as e:
        return [], CheckResult("file", False, f"Read error: {e}")


# ── Checks ─────────────────────────────────────────────────────────────────


def check_sample_count(report: SessionReport, min_samples: int = 10) -> CheckResult:
    if report.total_samples < min_samples:
        return CheckResult(
            "sample_count",
            False,
            f"Too few samples: {report.total_samples} (min {min_samples})",
        )
    return CheckResult(
        "sample_count",
        True,
        f"{report.total_samples} samples (L={report.left_samples}, R={report.right_samples})",
    )


def check_both_wheels(report: SessionReport) -> CheckResult:
    if report.left_samples == 0:
        return CheckResult("both_wheels", False, "No left wheel samples")
    if report.right_samples == 0:
        return CheckResult("both_wheels", False, "No right wheel samples")
    return CheckResult(
        "both_wheels",
        True,
        f"Both wheels present (L={report.left_samples}, R={report.right_samples})",
    )


def check_seq_gaps(report: SessionReport) -> CheckResult:
    total_gaps = len(report.left_seq_gaps) + len(report.right_seq_gaps)
    total_expected = report.left_samples + report.right_samples + total_gaps
    if total_expected == 0:
        return CheckResult("seq_gaps", False, "No samples to check")
    loss_pct = 100.0 * total_gaps / total_expected if total_expected else 0
    if loss_pct > 5.0:
        return CheckResult(
            "seq_gaps",
            False,
            f"Packet loss {loss_pct:.1f}% ({total_gaps} gaps / {total_expected} expected)",
        )
    return CheckResult(
        "seq_gaps",
        True,
        f"Packet loss {loss_pct:.1f}% ({total_gaps} gaps)",
    )


def check_effective_rate(
    report: SessionReport, expected_hz: float = 100.0, tolerance_pct: float = 5.0
) -> CheckResult:
    rates = []
    if report.left_effective_rate > 0:
        rates.append(("L", report.left_effective_rate))
    if report.right_effective_rate > 0:
        rates.append(("R", report.right_effective_rate))
    if not rates:
        return CheckResult("sample_rate", False, "No rate data")
    details = []
    all_ok = True
    for side, rate in rates:
        dev_pct = abs(rate - expected_hz) / expected_hz * 100
        ok = dev_pct <= tolerance_pct
        all_ok = all_ok and ok
        details.append(f"{side}: {rate:.1f} Hz (expected {expected_hz}, dev {dev_pct:.1f}%)")
    return CheckResult("sample_rate", all_ok, "; ".join(details))


def check_marker_diff(
    report: SessionReport, max_diff_ms: float = 10.0
) -> CheckResult:
    if not report.marker_diffs_ms:
        return CheckResult(
            "marker_diff",
            True,
            "No markers to compare (OK if no Mark Event was pressed)",
        )
    max_diff = max(report.marker_diffs_ms)
    avg_diff = sum(report.marker_diffs_ms) / len(report.marker_diffs_ms)
    if max_diff > max_diff_ms:
        return CheckResult(
            "marker_diff",
            False,
            f"Max marker diff {max_diff:.1f} ms > {max_diff_ms} ms threshold "
            f"(avg {avg_diff:.1f} ms, {len(report.marker_diffs_ms)} markers)",
        )
    return CheckResult(
        "marker_diff",
        True,
        f"Max marker diff {max_diff:.1f} ms (avg {avg_diff:.1f} ms, "
        f"{len(report.marker_diffs_ms)} markers)",
    )


# ── Analysis ───────────────────────────────────────────────────────────────


def analyze(samples: list[Sample]) -> SessionReport:
    report = SessionReport(csv_path="")
    report.total_samples = len(samples)

    left = [s for s in samples if s.wheel == "L"]
    right = [s for s in samples if s.wheel == "R"]
    report.left_samples = len(left)
    report.right_samples = len(right)

    # Markers
    report.markers = [s for s in samples if s.marker == 1]
    report.left_markers = [s for s in report.markers if s.wheel == "L"]
    report.right_markers = [s for s in report.markers if s.wheel == "R"]

    # Seq gaps (packet loss)
    for side_samples, gaps_list in [
        (left, report.left_seq_gaps),
        (right, report.right_seq_gaps),
    ]:
        if not side_samples:
            continue
        seqs = [s.seq for s in side_samples]
        for i in range(1, len(seqs)):
            if seqs[i] != seqs[i - 1] + 1:
                gaps_list.append((seqs[i - 1], seqs[i]))

    # Effective sample rate (from synced timestamps)
    for side_samples, attr in [
        (left, "left_effective_rate"),
        (right, "right_effective_rate"),
    ]:
        if len(side_samples) < 2:
            continue
        ts = sorted(s.timestamp_synced_ms for s in side_samples)
        duration_ms = ts[-1] - ts[0]
        if duration_ms > 0:
            rate = (len(ts) - 1) / (duration_ms / 1000.0)
            setattr(report, attr, rate)

    # Marker diff between L and R
    # Match markers by closest timestamp
    if report.left_markers and report.right_markers:
        for lm in report.left_markers:
            closest_r = min(
                report.right_markers,
                key=lambda r: abs(r.timestamp_synced_ms - lm.timestamp_synced_ms),
            )
            diff = abs(lm.timestamp_synced_ms - closest_r.timestamp_synced_ms)
            report.marker_diffs_ms.append(diff)

    return report


# ── Plotting ───────────────────────────────────────────────────────────────


def plot_session(samples: list[Sample], output_path: Path | None = None) -> None:
    """Plot accel/gyro for both wheels. Requires matplotlib."""
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("  (matplotlib not installed — skipping plot)")
        return

    left = sorted(
        [s for s in samples if s.wheel == "L"],
        key=lambda s: s.timestamp_synced_ms,
    )
    right = sorted(
        [s for s in samples if s.wheel == "R"],
        key=lambda s: s.timestamp_synced_ms,
    )

    fig, axes = plt.subplots(6, 1, figsize=(14, 18), sharex=True)
    cols = ["ax", "ay", "az", "gx", "gy", "gz"]
    titles = ["Accel X (g)", "Accel Y (g)", "Accel Z (g)",
              "Gyro X (dps)", "Gyro Y (dps)", "Gyro Z (dps)"]

    for ax, col, title in zip(axes, cols, titles):
        if left:
            t_l = [s.timestamp_synced_ms / 1000.0 for s in left]
            v_l = [getattr(s, col) for s in left]
            ax.plot(t_l, v_l, label="L", color="royalblue", alpha=0.8)
        if right:
            t_r = [s.timestamp_synced_ms / 1000.0 for s in right]
            v_r = [getattr(s, col) for s in right]
            ax.plot(t_r, v_r, label="R", color="coral", alpha=0.8)
        ax.set_ylabel(title)
        ax.legend(loc="upper right")
        ax.grid(True, alpha=0.3)

    # Mark markers as vertical lines
    for m in samples:
        if m.marker == 1:
            for ax in axes:
                ax.axvline(
                    m.timestamp_synced_ms / 1000.0,
                    color="green",
                    linestyle="--",
                    alpha=0.5,
                )

    axes[-1].set_xlabel("Synced time (s)")
    fig.suptitle("WheelAthlete Session — IMU (L vs R)", fontsize=14)
    plt.tight_layout()

    if output_path:
        plt.savefig(output_path, dpi=150)
        print(f"  Plot saved to {output_path}")
    else:
        plt.show()


# ── Main ───────────────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a WheelAthlete session CSV."
    )
    parser.add_argument("csv", type=Path, help="Path to session_*.csv")
    parser.add_argument(
        "--meta",
        type=Path,
        default=None,
        help="Optional session_<id>_meta.json for expected sample rate",
    )
    parser.add_argument(
        "--no-plot",
        action="store_true",
        help="Skip plotting (no matplotlib required)",
    )
    parser.add_argument(
        "--save-plot",
        type=Path,
        default=None,
        help="Save plot to this file instead of showing",
    )
    args = parser.parse_args()

    # Parse CSV
    samples, schema_err = parse_csv(args.csv)
    if schema_err:
        print(f"FAIL: {schema_err.name}: {schema_err.detail}")
        return 2

    print(f"Loaded {len(samples)} samples from {args.csv}")

    # Load meta for expected sample rate
    expected_hz = 100.0
    if args.meta and args.meta.exists():
        with args.meta.open() as f:
            meta = json.load(f)
        expected_hz = meta.get("sampleRateHz", 100.0)
        print(f"Meta: sampleRateHz={expected_hz}")

    # Analyze
    report = analyze(samples)
    report.csv_path = str(args.csv)

    # Run checks
    report.results.append(check_sample_count(report))
    report.results.append(check_both_wheels(report))
    report.results.append(check_seq_gaps(report))
    report.results.append(check_effective_rate(report, expected_hz=expected_hz))
    report.results.append(check_marker_diff(report))

    # Print results
    print("\n" + "-" * 50)
    print("Check Results:")
    print("-" * 50)
    for r in report.results:
        status = "PASS" if r.passed else "FAIL"
        print(f"  [{status}] {r.name}: {r.detail}")
    print("-" * 50)

    # Plot
    if not args.no_plot:
        print("\nGenerating plot...")
        plot_session(samples, output_path=args.save_plot)

    # Summary
    if report.all_passed:
        print("\n[OK] All checks passed -- session is valid.")
        return 0
    else:
        failed = [r.name for r in report.results if not r.passed]
        print(f"\n[FAIL] {len(failed)} check(s) failed: {', '.join(failed)}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
