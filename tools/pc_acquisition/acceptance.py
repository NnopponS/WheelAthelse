from __future__ import annotations

import argparse
import asyncio
import dataclasses
import json
import os
import statistics
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .journal import JournalReader, RecordKind
from .models import WheelSide
from .service import AcquisitionService
from .transport import BleakTransport


ACCEPTANCE_SCHEMA_VERSION = 1
MIN_RESEARCH_MTU = 185
DESIRED_START_SKEW_NS = 5_000_000
MAX_EFFECTIVE_RATE_ERROR_FRACTION = 0.05
EXPECTED_XIAO_HARDWARE_MODEL = 2
DEFAULT_EXPECTED_FIRMWARE = "1.8.0"


class AcceptanceRunError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class AcceptanceCase:
    case_id: str
    rate_hz: int
    duration_s: float
    distance_m: float
    cycles: int = 1
    description: str = ""

    def __post_init__(self) -> None:
        if self.rate_hz not in (50, 100, 200):
            raise ValueError("acceptance rate_hz must be 50, 100, or 200")
        if self.duration_s <= 0:
            raise ValueError("acceptance duration_s must be positive")
        if self.distance_m <= 0:
            raise ValueError("acceptance distance_m must be positive")
        if self.cycles < 1:
            raise ValueError("acceptance cycles must be >= 1")

    @property
    def planned_recording_s(self) -> float:
        return self.duration_s * self.cycles

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


@dataclass(frozen=True, slots=True)
class AcceptanceThresholds:
    min_mtu: int = MIN_RESEARCH_MTU
    max_effective_rate_error_fraction: float = MAX_EFFECTIVE_RATE_ERROR_FRACTION
    desired_start_skew_ns: int = DESIRED_START_SKEW_NS
    expected_hardware_model: int = EXPECTED_XIAO_HARDWARE_MODEL
    expected_firmware: str = DEFAULT_EXPECTED_FIRMWARE


DEFAULT_ACCEPTANCE_PLAN: tuple[AcceptanceCase, ...] = (
    AcceptanceCase(
        "50hz-120s-0p5m",
        50,
        120,
        0.5,
        description="50 Hz rate validation at close range",
    ),
    AcceptanceCase(
        "100hz-120s-0p5m",
        100,
        120,
        0.5,
        description="100 Hz short baseline",
    ),
    AcceptanceCase(
        "200hz-120s-0p5m",
        200,
        120,
        0.5,
        description="200 Hz high-rate validation",
    ),
    AcceptanceCase(
        "100hz-120s-2m",
        100,
        120,
        2.0,
        description="100 Hz medium-distance RF validation",
    ),
    AcceptanceCase(
        "100hz-120s-5m",
        100,
        120,
        5.0,
        description="100 Hz maximum planned-distance RF validation",
    ),
    AcceptanceCase(
        "100hz-600s-0p5m",
        100,
        600,
        0.5,
        description="100 Hz ten-minute sustained acquisition",
    ),
    AcceptanceCase(
        "100hz-startstop-20x-0p5m",
        100,
        10,
        0.5,
        cycles=20,
        description="20 synchronized Start/Stop lifecycle cycles",
    ),
    AcceptanceCase(
        "100hz-1800s-0p5m",
        100,
        1800,
        0.5,
        description="100 Hz thirty-minute sustained acceptance run",
    ),
)


def acceptance_plan_payload(
    cases: tuple[AcceptanceCase, ...] = DEFAULT_ACCEPTANCE_PLAN,
) -> dict[str, Any]:
    return {
        "schema_version": ACCEPTANCE_SCHEMA_VERSION,
        "type": "wheelathlete_physical_acceptance_plan",
        "cases": [case.to_dict() for case in cases],
        "planned_recording_s": sum(case.planned_recording_s for case in cases),
        "hard_requirements": {
            "two_xiao_boards": True,
            "minimum_mtu": MIN_RESEARCH_MTU,
            "sequence_gaps": 0,
            "duplicates": 0,
            "out_of_order": 0,
            "malformed_packets": 0,
            "host_queue_overflow": 0,
            "firmware_queue_drops": 0,
            "transport_failures": 0,
            "fifo_faults": 0,
            "fifo_dropped_samples": 0,
            "produced_equals_notified_equals_received_equals_journal": True,
            "start_skew_less_than_one_sample_period": True,
            "effective_rate_error_fraction_max": MAX_EFFECTIVE_RATE_ERROR_FRACTION,
            "final_quality": "GOOD",
        },
        "desired_requirements": {
            "start_skew_ns_max": DESIRED_START_SKEW_NS,
        },
    }


def _check(
    checks: list[dict[str, Any]],
    name: str,
    passed: bool,
    detail: str,
    *,
    hard: bool = True,
) -> None:
    checks.append(
        {
            "name": name,
            "passed": bool(passed),
            "hard": hard,
            "detail": detail,
        }
    )


def _as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


def _rssi_statistics(values: list[int]) -> dict[str, Any]:
    if not values:
        return {"samples": 0, "min_dbm": None, "max_dbm": None, "mean_dbm": None}
    return {
        "samples": len(values),
        "min_dbm": min(values),
        "max_dbm": max(values),
        "mean_dbm": statistics.fmean(values),
    }


def summarize_journal(
    journal_path: Path | str,
    *,
    expected_rate_hz: int | None = None,
    expected_duration_s: float | None = None,
    thresholds: AcceptanceThresholds = AcceptanceThresholds(),
) -> dict[str, Any]:
    """Create bounded-memory physical acceptance evidence from one `.waj`."""

    path = Path(journal_path)
    reader = JournalReader(path)
    validation = reader.validate()
    metadata: dict[str, Any] = {}
    final: dict[str, Any] = {}
    sample_counts = {"L": 0, "R": 0}
    sequence_counts = {
        "gap": 0,
        "duplicate": 0,
        "out_of_order": 0,
        "unknown": 0,
    }
    first_seq: dict[str, int | None] = {"L": None, "R": None}
    last_seq: dict[str, int | None] = {"L": None, "R": None}
    health: dict[str, dict[str, Any]] = {}
    sync: dict[str, list[dict[str, Any]]] = {"L": [], "R": []}
    start_events: list[dict[str, Any]] = []
    stop_events: dict[str, dict[str, Any]] = {}
    error_records: list[dict[str, Any]] = []

    for record in reader.iter_records():
        if record.kind is RecordKind.SAMPLE and record.sample is not None:
            received = record.sample
            side = received.side.value
            seq = received.sample.seq
            sample_counts[side] += 1
            if first_seq[side] is None:
                first_seq[side] = seq
            last_seq[side] = seq
            classification = received.sequence_class
            if classification == "gap":
                sequence_counts["gap"] += received.missing_before or 1
            elif classification in ("duplicate", "out_of_order"):
                sequence_counts[classification] += 1
            elif classification not in ("first", "contiguous"):
                sequence_counts["unknown"] += 1
            continue

        value = record.json_value or {}
        if record.kind is RecordKind.SESSION_META:
            metadata = dict(value)
        elif record.kind is RecordKind.SYNC:
            side = str(value.get("side", ""))
            if side in sync:
                sync[side].append(dict(value))
        elif record.kind is RecordKind.HEALTH:
            side = str(value.get("side", ""))
            if side in sample_counts:
                health[side] = dict(value)
        elif record.kind is RecordKind.EVENT:
            event_type = value.get("type")
            if event_type == "START":
                start_events.append(dict(value))
            elif event_type == "STOP":
                side = str(value.get("side", ""))
                if side in sample_counts:
                    stop_events[side] = dict(value)
        elif record.kind is RecordKind.ERROR:
            error_records.append(dict(value))
        elif record.kind is RecordKind.FINALIZE:
            final = dict(value)

    checks: list[dict[str, Any]] = []
    _check(
        checks,
        "journal_finalized",
        validation.finalized and not validation.truncated_tail and not validation.checksum_error,
        (
            f"finalized={validation.finalized}, truncated={validation.truncated_tail}, "
            f"checksum_error={validation.checksum_error}"
        ),
    )
    _check(
        checks,
        "final_quality_good",
        final.get("quality") == "GOOD",
        f"quality={final.get('quality')!r}, reasons={final.get('reasons', [])!r}",
    )
    _check(
        checks,
        "no_error_records",
        not error_records,
        f"error_records={len(error_records)}",
    )

    configured_rate = _as_int(metadata.get("sample_rate_hz"))
    rate_hz = expected_rate_hz or configured_rate
    if expected_rate_hz is not None:
        _check(
            checks,
            "configured_rate_matches_case",
            configured_rate == expected_rate_hz,
            f"journal={configured_rate}, expected={expected_rate_hz}",
        )

    boards = metadata.get("boards")
    boards = boards if isinstance(boards, dict) else {}
    for side in ("L", "R"):
        board = boards.get(side)
        board = board if isinstance(board, dict) else {}
        mtu = _as_int(board.get("mtu"))
        hardware_model = _as_int(board.get("hardware_model"))
        firmware = board.get("firmware")
        _check(
            checks,
            f"{side}_xiao_hardware",
            hardware_model == thresholds.expected_hardware_model,
            f"hardware_model={hardware_model}, expected={thresholds.expected_hardware_model}",
        )
        _check(
            checks,
            f"{side}_firmware",
            firmware == thresholds.expected_firmware,
            f"firmware={firmware!r}, expected={thresholds.expected_firmware!r}",
        )
        _check(
            checks,
            f"{side}_mtu",
            mtu is not None and mtu >= thresholds.min_mtu,
            f"mtu={mtu}, minimum={thresholds.min_mtu}",
        )
        _check(
            checks,
            f"{side}_has_samples",
            sample_counts[side] > 0,
            f"samples={sample_counts[side]}",
        )
        _check(
            checks,
            f"{side}_sequence_starts_zero",
            first_seq[side] == 0,
            f"first_seq={first_seq[side]}",
        )

    _check(
        checks,
        "zero_sequence_gaps",
        sequence_counts["gap"] == 0,
        f"missing_sequence_values={sequence_counts['gap']}",
    )
    _check(
        checks,
        "zero_duplicates",
        sequence_counts["duplicate"] == 0,
        f"duplicates={sequence_counts['duplicate']}",
    )
    _check(
        checks,
        "zero_out_of_order",
        sequence_counts["out_of_order"] == 0,
        f"out_of_order={sequence_counts['out_of_order']}",
    )
    _check(
        checks,
        "zero_unknown_sequence_class",
        sequence_counts["unknown"] == 0,
        f"unknown={sequence_counts['unknown']}",
    )

    start = start_events[-1] if start_events else {}
    acknowledged = set(start.get("acknowledged", [])) if isinstance(start.get("acknowledged"), list) else set()
    start_skew_ns = _as_int(start.get("start_skew_ns"))
    _check(
        checks,
        "start_acknowledged_both",
        acknowledged == {"L", "R"},
        f"acknowledged={sorted(acknowledged)}",
    )
    if rate_hz:
        hard_skew_ns = 1_000_000_000 / rate_hz
        _check(
            checks,
            "start_skew_below_one_sample",
            start_skew_ns is not None and start_skew_ns < hard_skew_ns,
            f"start_skew_ns={start_skew_ns}, sample_period_ns={hard_skew_ns:.0f}",
        )
    else:
        _check(checks, "start_skew_below_one_sample", False, "sample rate unavailable")
    _check(
        checks,
        "desired_start_skew",
        start_skew_ns is not None and start_skew_ns < thresholds.desired_start_skew_ns,
        f"start_skew_ns={start_skew_ns}, desired<{thresholds.desired_start_skew_ns}",
        hard=False,
    )

    for side in ("L", "R"):
        stop = stop_events.get(side, {})
        _check(
            checks,
            f"{side}_stop_acknowledged",
            stop.get("acknowledged") is True and not stop.get("error"),
            f"acknowledged={stop.get('acknowledged')}, error={stop.get('error')!r}",
        )

        side_health = health.get(side, {})
        produced = _as_int(side_health.get("produced"))
        notified = _as_int(side_health.get("notified"))
        queue_drops = _as_int(side_health.get("queue_drops"))
        transport_failures = _as_int(side_health.get("transport_failures"))
        queue_depth = _as_int(side_health.get("queue_depth"))
        fifo_faults = _as_int(side_health.get("fifo_faults"))
        fifo_drops = _as_int(side_health.get("fifo_dropped_samples"))
        _check(
            checks,
            f"{side}_count_integrity",
            produced == notified == sample_counts[side] and produced is not None,
            f"produced={produced}, notified={notified}, received={sample_counts[side]}",
        )
        _check(checks, f"{side}_firmware_queue_drops", queue_drops == 0, f"queue_drops={queue_drops}")
        _check(
            checks,
            f"{side}_transport_failures",
            transport_failures == 0,
            f"transport_failures={transport_failures}",
        )
        _check(checks, f"{side}_final_queue_drained", queue_depth == 0, f"queue_depth={queue_depth}")
        _check(checks, f"{side}_fifo_faults", fifo_faults == 0, f"fifo_faults={fifo_faults}")
        _check(
            checks,
            f"{side}_fifo_dropped_samples",
            fifo_drops == 0,
            f"fifo_dropped_samples={fifo_drops}",
        )

        sync_records = sync[side]
        pre = [item for item in sync_records if item.get("phase") != "post_stop"]
        post = [item for item in sync_records if item.get("phase") == "post_stop"]
        _check(
            checks,
            f"{side}_pre_record_sync",
            bool(pre),
            f"pre_sync_records={len(pre)}",
        )
        _check(
            checks,
            f"{side}_post_record_sync",
            bool(post),
            f"post_sync_records={len(post)}",
        )

    duration_s = final.get("duration_s")
    duration_value = float(duration_s) if isinstance(duration_s, (int, float)) else None
    if expected_duration_s is not None:
        tolerance_s = max(2.0, expected_duration_s * 0.05)
        _check(
            checks,
            "duration_matches_case",
            duration_value is not None and abs(duration_value - expected_duration_s) <= tolerance_s,
            (
                f"duration_s={duration_value}, expected={expected_duration_s}, "
                f"tolerance={tolerance_s}"
            ),
        )

    effective_rates: dict[str, float | None] = {"L": None, "R": None}
    if rate_hz and duration_value and duration_value > 0:
        for side in ("L", "R"):
            effective = sample_counts[side] / duration_value
            effective_rates[side] = effective
            error_fraction = abs(effective - rate_hz) / rate_hz
            _check(
                checks,
                f"{side}_effective_rate",
                error_fraction <= thresholds.max_effective_rate_error_fraction,
                (
                    f"effective={effective:.4f} Hz, target={rate_hz} Hz, "
                    f"error={error_fraction * 100:.3f}%"
                ),
            )
    else:
        for side in ("L", "R"):
            _check(checks, f"{side}_effective_rate", False, "duration/rate unavailable")

    journal_summary = final.get("journal")
    journal_summary = journal_summary if isinstance(journal_summary, dict) else {}
    journal_written = _as_int(journal_summary.get("samples_written"))
    expected_written = sample_counts["L"] + sample_counts["R"]
    _check(
        checks,
        "journal_count_integrity",
        journal_written == expected_written,
        f"journal_written={journal_written}, decoded_samples={expected_written}",
    )
    _check(
        checks,
        "journal_queue_overflow_zero",
        _as_int(journal_summary.get("queue_overflow_faults")) == 0,
        f"queue_overflow_faults={journal_summary.get('queue_overflow_faults')}",
    )
    _check(
        checks,
        "journal_no_fatal_fault",
        journal_summary.get("fatal_fault") in (None, {}),
        f"fatal_fault={journal_summary.get('fatal_fault')!r}",
    )

    hard_failures = [item for item in checks if item["hard"] and not item["passed"]]
    desired_failures = [item for item in checks if not item["hard"] and not item["passed"]]
    post_clock = {
        side: (next((item for item in reversed(sync[side]) if item.get("phase") == "post_stop"), None))
        for side in ("L", "R")
    }

    return {
        "schema_version": ACCEPTANCE_SCHEMA_VERSION,
        "type": "wheelathlete_journal_acceptance_evidence",
        "journal_path": str(path),
        "passed": not hard_failures,
        "validation": dataclasses.asdict(validation),
        "metadata": metadata,
        "sample_counts": sample_counts,
        "sequence_counts": sequence_counts,
        "first_seq": first_seq,
        "last_seq": last_seq,
        "effective_rates_hz": effective_rates,
        "health": health,
        "sync": sync,
        "post_clock": post_clock,
        "start": start,
        "stops": stop_events,
        "errors": error_records,
        "final": final,
        "checks": checks,
        "hard_failures": hard_failures,
        "desired_failures": desired_failures,
    }


def _write_json_atomic(path: Path, value: dict[str, Any]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.flush()
        os.fsync(handle.fileno())
    temp.replace(path)
    return path


async def _collect_scan_snapshots(
    service: AcquisitionService,
    *,
    rounds: int = 5,
    scan_timeout_s: float = 1.5,
    pause_s: float = 0.25,
) -> list[dict[str, Any]]:
    snapshots: list[dict[str, Any]] = []
    for index in range(rounds):
        result = await service.handle_command("scan", {"timeout_s": scan_timeout_s})
        devices = result.get("devices", [])
        snapshots.append(
            {
                "round": index + 1,
                "utc_ms": int(time.time() * 1000),
                "devices": devices if isinstance(devices, list) else [],
            }
        )
        if index + 1 < rounds and pause_s > 0:
            await asyncio.sleep(pause_s)
    return snapshots


def _candidate_ids(snapshots: list[dict[str, Any]]) -> list[str]:
    latest_rssi: dict[str, int] = {}
    seen_order: list[str] = []
    for snapshot in snapshots:
        devices = snapshot.get("devices", [])
        if not isinstance(devices, list):
            continue
        for device in devices:
            if not isinstance(device, dict):
                continue
            device_id = str(device.get("device_id", ""))
            if not device_id:
                continue
            if device_id not in seen_order:
                seen_order.append(device_id)
            rssi = _as_int(device.get("rssi"))
            if rssi is not None:
                latest_rssi[device_id] = rssi
    return sorted(seen_order, key=lambda item: latest_rssi.get(item, -999), reverse=True)


async def _connect_xiao_pair(
    service: AcquisitionService,
    snapshots: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    connected: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for device_id in _candidate_ids(snapshots):
        if len(connected) == 2:
            break
        try:
            info = await service.handle_command("connect", {"device_id": device_id})
        except Exception as exc:
            errors.append(f"{device_id}: {exc}")
            continue
        side = str(info.get("side", ""))
        hardware_model = _as_int(info.get("hardware_model"))
        if side not in ("L", "R"):
            errors.append(f"{device_id}: invalid side {side!r}")
            continue
        if hardware_model != EXPECTED_XIAO_HARDWARE_MODEL:
            await service.handle_command("disconnect", {"side": side})
            errors.append(
                f"{device_id}: hardware_model={hardware_model}, expected XIAO model 2"
            )
            continue
        connected[side] = dict(info)

    if set(connected) != {"L", "R"}:
        for side in tuple(connected):
            try:
                await service.handle_command("disconnect", {"side": side})
            except Exception:
                pass
        raise AcceptanceRunError(
            "could not connect one XIAO for each wheel; "
            f"connected={sorted(connected)}, errors={errors}"
        )
    return connected


def _rssi_by_side(
    snapshots: list[dict[str, Any]],
    connected: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    id_to_side = {
        str(info.get("device_id")): side
        for side, info in connected.items()
        if info.get("device_id") is not None
    }
    values: dict[str, list[int]] = {"L": [], "R": []}
    for snapshot in snapshots:
        devices = snapshot.get("devices", [])
        if not isinstance(devices, list):
            continue
        for device in devices:
            if not isinstance(device, dict):
                continue
            side = id_to_side.get(str(device.get("device_id")))
            rssi = _as_int(device.get("rssi"))
            if side is not None and rssi is not None:
                values[side].append(rssi)
    return {
        side: {"values_dbm": readings, **_rssi_statistics(readings)}
        for side, readings in values.items()
    }


def _preflight_pair(
    connected: dict[str, dict[str, Any]],
    thresholds: AcceptanceThresholds,
) -> list[str]:
    failures: list[str] = []
    for side in ("L", "R"):
        info = connected[side]
        mtu = _as_int(info.get("mtu"))
        if mtu is None or mtu < thresholds.min_mtu:
            failures.append(f"{side}: negotiated MTU {mtu} < {thresholds.min_mtu}")
        if _as_int(info.get("hardware_model")) != thresholds.expected_hardware_model:
            failures.append(f"{side}: not XIAO hardware model {thresholds.expected_hardware_model}")
        if info.get("firmware") != thresholds.expected_firmware:
            failures.append(
                f"{side}: firmware {info.get('firmware')!r} != {thresholds.expected_firmware!r}"
            )
    return failures


async def run_physical_case(
    case: AcceptanceCase,
    *,
    journal_root: Path,
    thresholds: AcceptanceThresholds = AcceptanceThresholds(),
    prompt_for_placement: bool = True,
    scan_rounds: int = 5,
    scan_timeout_s: float = 1.5,
) -> dict[str, Any]:
    """Run one real two-XIAO case through the production acquisition service."""

    if prompt_for_placement:
        await asyncio.to_thread(
            input,
            (
                f"\n[{case.case_id}] Place both XIAO sensors approximately "
                f"{case.distance_m:g} m from this PC, keep the wheelchair setup "
                "in the intended test orientation, then press Enter to scan... "
            ),
        )

    result: dict[str, Any] = {
        "schema_version": ACCEPTANCE_SCHEMA_VERSION,
        "type": "wheelathlete_physical_acceptance_case",
        "case": case.to_dict(),
        "started_utc_ms": int(time.time() * 1000),
        "status": "RUNNING",
        "passed": False,
        "cycles": [],
    }
    service = AcquisitionService(BleakTransport(), journal_root=journal_root)
    try:
        snapshots = await _collect_scan_snapshots(
            service,
            rounds=scan_rounds,
            scan_timeout_s=scan_timeout_s,
        )
        result["scan_snapshots"] = snapshots
        connected = await _connect_xiao_pair(service, snapshots)
        result["connected"] = connected
        result["rssi"] = _rssi_by_side(snapshots, connected)
        preflight = _preflight_pair(connected, thresholds)
        result["preflight_failures"] = preflight
        if preflight:
            raise AcceptanceRunError("; ".join(preflight))

        for side in ("L", "R"):
            await service.handle_command(
                "configure",
                {"side": side, "sample_rate_hz": case.rate_hz},
            )

        for cycle in range(1, case.cycles + 1):
            acceptance_meta = {
                "schema_version": ACCEPTANCE_SCHEMA_VERSION,
                "case_id": case.case_id,
                "cycle": cycle,
                "cycles_total": case.cycles,
                "rate_hz": case.rate_hz,
                "expected_duration_s": case.duration_s,
                "operator_declared_distance_m": case.distance_m,
                "rssi": result["rssi"],
            }
            try:
                start = await service.handle_command(
                    "start_record",
                    {
                        "athlete": "PHYSICAL_ACCEPTANCE",
                        "topic": "PC Physical Acceptance",
                        "trial_number": cycle,
                        "notes": (
                            f"case={case.case_id}; cycle={cycle}/{case.cycles}; "
                            f"distance={case.distance_m:g}m"
                        ),
                        "sample_rate_hz": case.rate_hz,
                        "tags": ["physical-acceptance", case.case_id],
                        "acceptance": acceptance_meta,
                        "sync_count": 10,
                        "lead_time_s": 3.0,
                        "ack_timeout_s": 1.0,
                    },
                )
                await asyncio.sleep(case.duration_s)
                end = await service.handle_command("end_record", {})
                evidence = summarize_journal(
                    end["journal_path"],
                    expected_rate_hz=case.rate_hz,
                    expected_duration_s=case.duration_s,
                    thresholds=thresholds,
                )
                result["cycles"].append(
                    {
                        "cycle": cycle,
                        "status": "PASS" if evidence["passed"] else "FAIL",
                        "passed": evidence["passed"],
                        "start": start,
                        "end": end,
                        "evidence": evidence,
                    }
                )
            except Exception as exc:
                result["cycles"].append(
                    {
                        "cycle": cycle,
                        "status": "ERROR",
                        "passed": False,
                        "error": str(exc),
                    }
                )
                break

        result["passed"] = (
            len(result["cycles"]) == case.cycles
            and all(item.get("passed") is True for item in result["cycles"])
        )
        result["status"] = "PASS" if result["passed"] else "FAIL"
    except Exception as exc:
        result["status"] = "ERROR"
        result["error"] = str(exc)
        result["passed"] = False
    finally:
        result["finished_utc_ms"] = int(time.time() * 1000)
        await service.close()
    return result


def aggregate_acceptance_report(
    case_results: list[dict[str, Any]],
    *,
    plan: tuple[AcceptanceCase, ...] = DEFAULT_ACCEPTANCE_PLAN,
) -> dict[str, Any]:
    by_id = {
        str(item.get("case", {}).get("case_id")): item
        for item in case_results
        if isinstance(item.get("case"), dict)
    }
    planned_ids = [case.case_id for case in plan]
    missing = [case_id for case_id in planned_ids if case_id not in by_id]
    failed = [
        case_id
        for case_id in planned_ids
        if case_id in by_id and by_id[case_id].get("passed") is not True
    ]
    passed = not missing and not failed
    return {
        "schema_version": ACCEPTANCE_SCHEMA_VERSION,
        "type": "wheelathlete_physical_acceptance_report",
        "generated_utc_ms": int(time.time() * 1000),
        "status": "PASS" if passed else ("BLOCKED" if missing else "FAIL"),
        "passed": passed,
        "planned_case_ids": planned_ids,
        "completed_case_ids": [case_id for case_id in planned_ids if case_id in by_id],
        "missing_case_ids": missing,
        "failed_case_ids": failed,
        "cases": [by_id[case_id] for case_id in planned_ids if case_id in by_id],
        "physical_claims_allowed": passed,
    }


def _case_by_id(case_id: str) -> AcceptanceCase:
    for case in DEFAULT_ACCEPTANCE_PLAN:
        if case.case_id == case_id:
            return case
    raise KeyError(case_id)


def _print_plan() -> None:
    print("WheelAthlete two-XIAO physical acceptance plan")
    print("=" * 72)
    for case in DEFAULT_ACCEPTANCE_PLAN:
        cycle_text = f" x {case.cycles} cycles" if case.cycles > 1 else ""
        print(
            f"{case.case_id:30} {case.rate_hz:3} Hz  "
            f"{case.duration_s:6.0f} s{cycle_text:13}  {case.distance_m:g} m"
        )
    total_min = sum(case.planned_recording_s for case in DEFAULT_ACCEPTANCE_PLAN) / 60
    print(f"\nPlanned raw recording time: {total_min:.1f} minutes")
    print("Actual wall time is longer because each recording performs pre/post sync.")


async def _run_matrix(args: argparse.Namespace) -> int:
    journal_root = Path(args.journal_root)
    output_root = Path(args.output_root) if args.output_root else journal_root / "acceptance"
    output_root.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    for case in DEFAULT_ACCEPTANCE_PLAN:
        case_result = await run_physical_case(
            case,
            journal_root=journal_root,
            thresholds=AcceptanceThresholds(expected_firmware=args.expected_firmware),
            prompt_for_placement=not args.yes,
        )
        results.append(case_result)
        case_file = output_root / f"{case.case_id}.json"
        _write_json_atomic(case_file, case_result)
        print(f"{case.case_id}: {case_result['status']} -> {case_file}")
        if not case_result["passed"] and not args.continue_on_failure:
            print("Stopping matrix after first failed case. Fix the issue before long runs.")
            break

    report = aggregate_acceptance_report(results)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    report_path = output_root / f"physical-acceptance-{stamp}.json"
    _write_json_atomic(report_path, report)
    print(f"Overall: {report['status']} -> {report_path}")
    return 0 if report["passed"] else 2


async def _run_one_case(args: argparse.Namespace) -> int:
    try:
        case = _case_by_id(args.case_id)
    except KeyError:
        valid = ", ".join(case.case_id for case in DEFAULT_ACCEPTANCE_PLAN)
        raise SystemExit(f"unknown case {args.case_id!r}; valid cases: {valid}")
    journal_root = Path(args.journal_root)
    output_root = Path(args.output_root) if args.output_root else journal_root / "acceptance"
    result = await run_physical_case(
        case,
        journal_root=journal_root,
        thresholds=AcceptanceThresholds(expected_firmware=args.expected_firmware),
        prompt_for_placement=not args.yes,
    )
    output = output_root / f"{case.case_id}.json"
    _write_json_atomic(output, result)
    print(json.dumps({"status": result["status"], "output": str(output)}, indent=2))
    return 0 if result["passed"] else 2


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="WheelAthlete two-XIAO physical acceptance harness"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="show the prescribed physical matrix")
    plan.add_argument("--json", dest="json_path")

    summarize = sub.add_parser("summarize", help="evaluate one finalized .waj")
    summarize.add_argument("journal")
    summarize.add_argument("--expected-rate", type=int)
    summarize.add_argument("--expected-duration", type=float)
    summarize.add_argument("--expected-firmware", default=DEFAULT_EXPECTED_FIRMWARE)
    summarize.add_argument("--out")

    for name, help_text in (
        ("run-case", "execute one real physical acceptance case"),
        ("run-matrix", "execute the complete prescribed physical matrix"),
    ):
        run = sub.add_parser(name, help=help_text)
        if name == "run-case":
            run.add_argument("case_id")
        run.add_argument(
            "--journal-root",
            default=str(Path.home() / "Documents" / "WheelAthlete" / "PC Sessions"),
        )
        run.add_argument("--output-root")
        run.add_argument("--expected-firmware", default=DEFAULT_EXPECTED_FIRMWARE)
        run.add_argument(
            "--yes",
            action="store_true",
            help="do not pause for operator distance-placement confirmation",
        )
        if name == "run-matrix":
            run.add_argument(
                "--continue-on-failure",
                action="store_true",
                help="continue after a failed case instead of stopping fail-closed",
            )
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    if args.command == "plan":
        _print_plan()
        if args.json_path:
            output = _write_json_atomic(Path(args.json_path), acceptance_plan_payload())
            print(f"Plan JSON: {output}")
        return
    if args.command == "summarize":
        evidence = summarize_journal(
            args.journal,
            expected_rate_hz=args.expected_rate,
            expected_duration_s=args.expected_duration,
            thresholds=AcceptanceThresholds(expected_firmware=args.expected_firmware),
        )
        if args.out:
            _write_json_atomic(Path(args.out), evidence)
        print(json.dumps(evidence, indent=2, sort_keys=True))
        raise SystemExit(0 if evidence["passed"] else 2)
    if args.command == "run-case":
        raise SystemExit(asyncio.run(_run_one_case(args)))
    if args.command == "run-matrix":
        raise SystemExit(asyncio.run(_run_matrix(args)))
    parser.error(f"unsupported command {args.command}")


if __name__ == "__main__":
    main()
