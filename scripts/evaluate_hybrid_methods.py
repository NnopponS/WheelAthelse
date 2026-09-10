#!/usr/bin/env python
"""Reproducible evaluation and benchmark script comparing odometry methods.

Compares across all accepted C3D + dual-IMU trials:
1. Baseline Classical (`classical_xy_yaw_v1`)
2. Deep Residual BiGRU (`torch_residual_v1`)
3. Slalom Calibrated v3 (`slalom_calibrated_course_v3`)
4. Unified Hybrid Method (PINN + InEKF/ZARU + ICR + Smoother)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import numpy as np
import torch

# Add BiWheel3D root to sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
BIWHEEL_ROOT = PROJECT_ROOT / "BiWheel3D"

if str(BIWHEEL_ROOT) not in sys.path:
    sys.path.insert(0, str(BIWHEEL_ROOT))
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from biwheel3d.hybrid_estimator import HybridEstimatorConfig, run_hybrid_estimator
from biwheel3d.schema import Trial
from biwheel3d.slalom_calibrator_v3 import apply_slalom_calibrated_v3
from biwheel3d.torch_residual import (
    Normalizer,
    ResidualBiGRU,
    integrate_rates_np,
    load_sequences,
    predict_sequence,
)


def compute_metrics(
    pred_rates: np.ndarray,
    gt_xy: np.ndarray,
    gt_yaw: np.ndarray,
    target_rates: np.ndarray,
    mask: np.ndarray,
    dt: float = 0.05,
    pred_xy: np.ndarray | None = None,
    pred_yaw: np.ndarray | None = None,
) -> dict[str, float]:
    """Calculate trajectory and rate error metrics against ground truth."""
    if pred_xy is None or pred_yaw is None:
        pred_xy, pred_yaw = integrate_rates_np(pred_rates, dt=dt)
    valid = np.asarray(mask, dtype=bool)

    err_xy = np.linalg.norm(pred_xy - gt_xy, axis=1)
    err_yaw = np.degrees(pred_yaw - gt_yaw)
    endpoint_err = float(np.linalg.norm(pred_xy[-1] - gt_xy[-1]))

    ate_rmse = float(np.sqrt(np.mean(err_xy[valid] ** 2))) if valid.any() else 0.0
    heading_rmse = float(np.sqrt(np.mean(err_yaw[valid] ** 2))) if valid.any() else 0.0

    speed_mae = float(np.mean(np.abs(pred_rates[valid, 0] - target_rates[valid, 0]))) if valid.any() else 0.0
    yaw_rate_mae = float(np.degrees(np.mean(np.abs(pred_rates[valid, 1] - target_rates[valid, 1])))) if valid.any() else 0.0

    return {
        "ate_rmse_m": ate_rmse,
        "heading_rmse_deg": heading_rmse,
        "endpoint_error_m": endpoint_err,
        "speed_mae_mps": speed_mae,
        "yaw_rate_mae_degps": yaw_rate_mae,
    }


def load_torch_model(model_path: Path) -> tuple[ResidualBiGRU, Normalizer, dict[str, Any]]:
    """Load trained PyTorch Residual BiGRU model and normalizer."""
    checkpoint = torch.load(model_path, map_location="cpu", weights_only=False)
    normalizer = Normalizer.from_dict(checkpoint["normalizer"])
    model_cfg = checkpoint["model"]
    model = ResidualBiGRU(
        model_cfg["input_size"],
        normalizer.residual_scale,
        hidden_size=model_cfg["hidden_size"],
        num_layers=model_cfg["num_layers"],
        dropout=model_cfg["dropout"],
        bidirectional=model_cfg["bidirectional"],
    )
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    return model, normalizer, checkpoint


def format_markdown_table(rows: list[dict[str, Any]]) -> str:
    """Format quantitative evaluation records into a GitHub markdown table."""
    headers = [
        "Trial",
        "Split",
        "Condition",
        "Classic ATE (m)",
        "Torch ATE (m)",
        "Slalom v3 ATE (m)",
        "Hybrid ATE (m)",
        "Classic Head (deg)",
        "Torch Head (deg)",
        "Hybrid Head (deg)",
        "Classic End (m)",
        "Torch End (m)",
        "Hybrid End (m)",
    ]
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]

    for r in rows:
        lines.append(
            f"| {r['trial_id']} | {r['split']} | {r['condition']} | "
            f"{r['classic']['ate_rmse_m']:.3f} | {r['torch']['ate_rmse_m']:.3f} | {r['slalom_v3']['ate_rmse_m']:.3f} | **{r['hybrid']['ate_rmse_m']:.3f}** | "
            f"{r['classic']['heading_rmse_deg']:.1f} | {r['torch']['heading_rmse_deg']:.1f} | **{r['hybrid']['heading_rmse_deg']:.1f}** | "
            f"{r['classic']['endpoint_error_m']:.3f} | {r['torch']['endpoint_error_m']:.3f} | **{r['hybrid']['endpoint_error_m']:.3f}** |"
        )
    return "\n".join(lines)


def format_macro_summary(rows: list[dict[str, Any]]) -> str:
    """Format macro averages grouped by split and condition."""
    splits = ["train", "val", "test", "overall"]
    lines = [
        "| Group | Count | Classic ATE (m) | Torch ATE (m) | Slalom v3 ATE (m) | Hybrid ATE (m) | Classic Head (deg) | Torch Head (deg) | Hybrid Head (deg) |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]

    for sp in splits:
        matching = rows if sp == "overall" else [r for r in rows if r["split"] == sp]
        if not matching:
            continue
        c_ate = float(np.mean([r["classic"]["ate_rmse_m"] for r in matching]))
        t_ate = float(np.mean([r["torch"]["ate_rmse_m"] for r in matching]))
        v_ate = float(np.mean([r["slalom_v3"]["ate_rmse_m"] for r in matching]))
        h_ate = float(np.mean([r["hybrid"]["ate_rmse_m"] for r in matching]))

        c_h = float(np.mean([r["classic"]["heading_rmse_deg"] for r in matching]))
        t_h = float(np.mean([r["torch"]["heading_rmse_deg"] for r in matching]))
        h_h = float(np.mean([r["hybrid"]["heading_rmse_deg"] for r in matching]))

        lines.append(
            f"| **{sp.upper()}** | {len(matching)} | {c_ate:.3f} | {t_ate:.3f} | {v_ate:.3f} | **{h_ate:.3f}** | {c_h:.1f} | {t_h:.1f} | **{h_h:.1f}** |"
        )

    lines.append("")
    lines.append("### Condition Breakdown (Macro Average)")
    lines.append("")
    lines.append(
        "| Condition | Count | Classic ATE (m) | Torch ATE (m) | Slalom v3 ATE (m) | Hybrid ATE (m) | Classic Head (deg) | Hybrid Head (deg) |"
    )
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")

    conditions = sorted(list({r["condition"] for r in rows}))
    for cond in conditions:
        matching = [r for r in rows if r["condition"] == cond]
        c_ate = float(np.mean([r["classic"]["ate_rmse_m"] for r in matching]))
        t_ate = float(np.mean([r["torch"]["ate_rmse_m"] for r in matching]))
        v_ate = float(np.mean([r["slalom_v3"]["ate_rmse_m"] for r in matching]))
        h_ate = float(np.mean([r["hybrid"]["ate_rmse_m"] for r in matching]))

        c_h = float(np.mean([r["classic"]["heading_rmse_deg"] for r in matching]))
        h_h = float(np.mean([r["hybrid"]["heading_rmse_deg"] for r in matching]))

        lines.append(
            f"| **{cond}** | {len(matching)} | {c_ate:.3f} | {t_ate:.3f} | {v_ate:.3f} | **{h_ate:.3f}** | {c_h:.1f} | **{h_h:.1f}** |"
        )

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate and benchmark odometry methods.")
    parser.add_argument("--splits", nargs="+", default=["train", "val", "test"], help="Dataset splits to evaluate")
    parser.add_argument(
        "--output_json",
        default="BiWheel3D/results/hybrid_evaluation/benchmark_results.json",
        help="Path to output results JSON",
    )
    parser.add_argument(
        "--output_report",
        default="BiWheel3D/results/hybrid_evaluation/BENCHMARK_REPORT.md",
        help="Path to output markdown report",
    )
    args = parser.parse_args()

    # Load torch config and model
    torch_cfg_path = BIWHEEL_ROOT / "configs/torch_residual_v1.json"
    torch_cfg = json.loads(torch_cfg_path.read_text(encoding="utf-8"))
    model_path = BIWHEEL_ROOT / "models/experimental/torch_residual_v1/model.pt"
    model, normalizer, chkpt = load_torch_model(model_path)

    # Load slalom calibrator v3 config
    slalom_v3_cfg_path = BIWHEEL_ROOT / "configs/slalom_calibrated_course_v3.json"
    slalom_v3_cfg = json.loads(slalom_v3_cfg_path.read_text(encoding="utf-8"))

    # Load sequences across requested splits
    processed_dir = BIWHEEL_ROOT / torch_cfg["data"]["processed_dir"]
    trace_dir = BIWHEEL_ROOT / torch_cfg["data"]["support_trace_dir"]
    seqs = load_sequences(
        processed_dir,
        trace_dir,
        chkpt["baseline_recipe"],
        splits=args.splits,
    )
    print(f"Loaded {len(seqs)} sequences across splits {args.splits}")

    results = []
    device = torch.device("cpu")

    for s in seqs:
        trial_path = processed_dir / f"{s.trial_id}.npz"
        tr = Trial.load(trial_path)

        # 1. Baseline Classical (classical_xy_yaw_v1)
        classic_rates = s.base_current
        m_classic = compute_metrics(classic_rates, s.gt_xy, s.gt_yaw, s.target, s.target_mask)

        # 2. Deep Residual BiGRU (torch_residual_v1)
        torch_rates = predict_sequence(model, s, normalizer, device)
        m_torch = compute_metrics(torch_rates, s.gt_xy, s.gt_yaw, s.target, s.target_mask)

        # 3. Slalom Calibrated v3 (slalom_calibrated_course_v3)
        if s.condition == "SL":
            slalom_v3_rates = apply_slalom_calibrated_v3(
                torch_rates, s.base_research, s.base_current, slalom_v3_cfg
            ).rates
        else:
            slalom_v3_rates = torch_rates
        m_slalom_v3 = compute_metrics(slalom_v3_rates, s.gt_xy, s.gt_yaw, s.target, s.target_mask)

        # 4. Unified Hybrid Method (PINN + InEKF/ZARU + ICR + Smoother)
        cfg = HybridEstimatorConfig(
            wheel_radius_m=tr.meta.R,
            track_width_m=tr.meta.L_hub,
            camber_deg=15.0,
            dt=0.05,
            gyro_scale=1.102644416543689,
            chassis_yaw_scale=1.1711125569290826,
            fuse_chassis_yaw=True,
            yaw_delay_frames=0,
            enable_rts_smoother=True,
        )
        hyb = run_hybrid_estimator(tr.imu_dual_windows, config=cfg, dt=0.05)
        hybrid_rates = hyb["rates"]
        m_hybrid = compute_metrics(
            hybrid_rates,
            s.gt_xy,
            s.gt_yaw,
            s.target,
            s.target_mask,
            pred_xy=hyb["xyz"][:, :2],
            pred_yaw=hyb["psi"],
        )

        row = {
            "trial_id": s.trial_id,
            "split": s.split,
            "condition": s.condition,
            "samples": s.n,
            "supported_samples": int(s.target_mask.sum()),
            "classic": m_classic,
            "torch": m_torch,
            "slalom_v3": m_slalom_v3,
            "hybrid": m_hybrid,
        }
        results.append(row)
        print(
            f"{s.trial_id:10s} [{s.split:5s}|{s.condition:7s}] | "
            f"Classic ATE: {m_classic['ate_rmse_m']:.3f}m | "
            f"Torch ATE: {m_torch['ate_rmse_m']:.3f}m | "
            f"Slalom v3 ATE: {m_slalom_v3['ate_rmse_m']:.3f}m | "
            f"Hybrid ATE: {m_hybrid['ate_rmse_m']:.3f}m"
        )

    # Format Markdown Report
    table_md = format_markdown_table(results)
    summary_md = format_macro_summary(results)

    report_text = f"""# Benchmark Comparison: Classical vs PyTorch Residual vs Slalom v3 vs Unified Hybrid

This benchmark evaluates 4 wheelchair odometry methods across all {len(results)} accepted real C3D + dual-IMU trials:
1. **Baseline Classical (`classical_xy_yaw_v1`)**: Dual-hub gz with pause-aware burst delay and complementary chassis gyro.
2. **Deep Residual BiGRU (`torch_residual_v1`)**: 88-dimensional multi-window BiGRU predicting additive corrections to speed and yaw rate.
3. **Slalom Calibrated v3 (`slalom_calibrated_course_v3`)**: Deterministic train-calibrated Slalom adapter with closed-course loop constraint.
4. **Unified Hybrid Method (`unified_hybrid`)**: Integrates non-LLM elements of the 5 recommended methods:
   - Method 1: Camber projection (15 deg) + neural physics-informed slip residual
   - Method 2: Multi-Scale temporal feature extraction (transient shock vs kinematic scales)
   - Method 3: Biomechanical phase classification (Pause, Push, Coast, Turn, Straight) with Dynamic ZUPT/ZARU InEKF
   - Method 4: Rauch-Tung-Striebel (RTS) backward trajectory smoother and pose optimization
   - Method 5: Frequency-decoupled contact shock filtering and Skid-Steer ICR effective track width scaling

---

## Macro Summary by Split and Condition

{summary_md}

---

## Per-Trial Quantitative Evaluation Table

{table_md}
"""

    out_json_path = (PROJECT_ROOT / args.output_json).resolve()
    out_json_path.parent.mkdir(parents=True, exist_ok=True)
    out_json_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"\nSaved results JSON to: {out_json_path}")

    out_report_path = (PROJECT_ROOT / args.output_report).resolve()
    out_report_path.parent.mkdir(parents=True, exist_ok=True)
    out_report_path.write_text(report_text, encoding="utf-8")
    print(f"Saved benchmark report Markdown to: {out_report_path}")

    # Also print markdown table to stdout
    print("\n" + "=" * 80)
    print(summary_md)
    print("=" * 80)
    print(table_md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
