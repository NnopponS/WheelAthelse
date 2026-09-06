import asyncio
import struct
import time
from pathlib import Path
from unittest.mock import AsyncMock

from tools.pc_acquisition.acceptance import (
    DEFAULT_ACCEPTANCE_PLAN,
    AcceptanceThresholds,
    acceptance_plan_payload,
    aggregate_acceptance_report,
    summarize_journal,
)
from tools.pc_acquisition.clock_sync import ClockModel
from tools.pc_acquisition.journal import JournalReader, JournalRecorder, RecordKind
from tools.pc_acquisition.lifecycle import StartResult
from tools.pc_acquisition.models import ImuSample, ReceivedSample, WheelSide
from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import BATTERY_LEVEL_UUID, CONFIG_UUID, INFO_UUID


def _sample(side: WheelSide, seq: int, *, gap: bool = False) -> ReceivedSample:
    return ReceivedSample(
        side=side,
        sample=ImuSample(
            seq=seq,
            t_device_us=seq * 10_000,
            ax=1,
            ay=2,
            az=3,
            gx=4,
            gy=5,
            gz=6,
        ),
        arrival_ns=1_000_000_000 + seq * 10_000_000,
        packet_id=seq // 10,
        sequence_class=("gap" if gap else ("first" if seq == 0 else "contiguous")),
        missing_before=1 if gap else 0,
    )


def _good_journal(tmp_path: Path, *, inject_gap: bool = False) -> Path:
    recorder = JournalRecorder(
        tmp_path,
        session_id="12345678-1111-2222-3333-123456789abc",
        fsync_every_records=512,
    )
    recorder.append_metadata(
        {
            "athlete": "PHYSICAL_ACCEPTANCE",
            "topic": "PC Physical Acceptance",
            "trial_number": 1,
            "sample_rate_hz": 100,
            "acceptance": {
                "case_id": "synthetic-good",
                "operator_declared_distance_m": 0.5,
            },
            "boards": {
                "L": {
                    "device_id": "left",
                    "hardware_model": 2,
                    "firmware": "1.8.0",
                    "mtu": 247,
                },
                "R": {
                    "device_id": "right",
                    "hardware_model": 2,
                    "firmware": "1.8.0",
                    "mtu": 247,
                },
            },
        }
    )
    for side in ("L", "R"):
        recorder.append_json(
            RecordKind.SYNC,
            {
                "side": side,
                "best_rtt_ns": 1_000_000,
                "median_rtt_ns": 1_500_000,
                "drift_ppm": 5.0,
                "observation_count": 10,
            },
        )
    recorder.append_json(
        RecordKind.EVENT,
        {
            "type": "START",
            "acknowledged": ["L", "R"],
            "start_skew_ns": 2_000_000,
            "pc_start_ns": 1_000_000_000,
        },
    )

    for seq in range(200):
        recorder.submit_sample(
            _sample(WheelSide.LEFT, seq, gap=inject_gap and seq == 50)
        )
        recorder.submit_sample(_sample(WheelSide.RIGHT, seq))
    recorder.wait_until_idle()

    for side in ("L", "R"):
        recorder.append_json(
            RecordKind.HEALTH,
            {
                "side": side,
                "state": 0,
                "produced": 200,
                "notified": 200,
                "queue_drops": 0,
                "transport_failures": 0,
                "queue_depth": 0,
                "fifo_faults": 0,
                "fifo_dropped_samples": 0,
            },
        )
        recorder.append_json(
            RecordKind.EVENT,
            {
                "type": "STOP",
                "side": side,
                "acknowledged": True,
                "write_attempts": 1,
                "error": None,
            },
        )
        recorder.append_json(
            RecordKind.SYNC,
            {
                "phase": "post_stop",
                "side": side,
                "best_rtt_ns": 900_000,
                "median_rtt_ns": 1_400_000,
                "drift_ppm": 7.0,
                "observation_count": 13,
            },
        )

    return recorder.finalize(
        {
            "quality": "GOOD",
            "duration_s": 2.0,
            "reasons": [],
            "journal": {
                "samples_written": recorder.metrics.samples_written,
                "queue_high_water": recorder.metrics.queue_high_water,
                "queue_overflow_faults": 0,
                "max_write_latency_ns": recorder.metrics.max_write_latency_ns,
                "fatal_fault": None,
            },
        }
    )


def test_default_physical_matrix_covers_rates_distances_long_run_and_20_cycles():
    payload = acceptance_plan_payload()
    assert payload["planned_recording_s"] == 3200
    assert {case.rate_hz for case in DEFAULT_ACCEPTANCE_PLAN} == {50, 100, 200}
    assert {case.distance_m for case in DEFAULT_ACCEPTANCE_PLAN} >= {0.5, 2.0, 5.0}
    assert any(case.duration_s == 1800 for case in DEFAULT_ACCEPTANCE_PLAN)
    assert any(case.cycles == 20 for case in DEFAULT_ACCEPTANCE_PLAN)
    assert payload["hard_requirements"]["produced_equals_notified_equals_received_equals_journal"]


def test_acceptance_summary_streams_good_journal_and_passes_all_hard_checks(tmp_path: Path):
    path = _good_journal(tmp_path)
    evidence = summarize_journal(
        path,
        expected_rate_hz=100,
        expected_duration_s=2.0,
        thresholds=AcceptanceThresholds(expected_firmware="1.8.0"),
    )
    assert evidence["passed"]
    assert evidence["sample_counts"] == {"L": 200, "R": 200}
    assert evidence["sequence_counts"] == {
        "gap": 0,
        "duplicate": 0,
        "out_of_order": 0,
        "unknown": 0,
    }
    assert evidence["post_clock"]["L"]["drift_ppm"] == 7.0
    assert evidence["post_clock"]["R"]["drift_ppm"] == 7.0
    assert not evidence["hard_failures"]
    assert len(list(JournalReader(path).iter_records())) > 400


def test_acceptance_summary_rejects_sequence_loss_even_if_finalize_claims_good(tmp_path: Path):
    path = _good_journal(tmp_path, inject_gap=True)
    evidence = summarize_journal(path, expected_rate_hz=100, expected_duration_s=2.0)
    assert not evidence["passed"]
    assert evidence["sequence_counts"]["gap"] == 1
    assert "zero_sequence_gaps" in {
        item["name"] for item in evidence["hard_failures"]
    }


def test_aggregate_report_is_blocked_until_every_prescribed_case_has_real_result():
    report = aggregate_acceptance_report([])
    assert report["status"] == "BLOCKED"
    assert not report["passed"]
    assert not report["physical_claims_allowed"]
    assert report["missing_case_ids"] == [
        case.case_id for case in DEFAULT_ACCEPTANCE_PLAN
    ]


def _info() -> bytes:
    return (
        bytes([0x4C, 1, 7, 0, 1, 3])
        + struct.pack("<ff", 4 / 32768, 2000 / 32768)
        + bytes([2, 1])
    )


def _config() -> bytes:
    return (
        b"Research-L".ljust(24, b"\x00")
        + bytes([0x4C])
        + struct.pack("<H", 100)
        + bytes([1, 7, 0, 1])
    )


def test_start_record_persists_physical_acceptance_metadata(tmp_path: Path):
    async def scenario():
        transport = FakeBleTransport()
        transport.read_values[("left", INFO_UUID)] = _info()
        transport.read_values[("left", CONFIG_UUID)] = _config()
        transport.read_values[("left", BATTERY_LEVEL_UUID)] = bytes([90])
        transport.mtu["left"] = 247
        service = AcquisitionService(transport, journal_root=tmp_path)
        await service.handle_command("connect", {"device_id": "left"})

        now_ns = time.monotonic_ns()
        model = ClockModel.nominal(
            device_us=1_000_000,
            pc_ns=now_ns,
            rtt_ns=1_000_000,
        )
        service.lifecycle.synchronize = AsyncMock(return_value=model)
        service.lifecycle.scheduled_start = AsyncMock(
            return_value=StartResult(
                pc_start_ns=now_ns + 1_000_000,
                acknowledged=frozenset({WheelSide.LEFT}),
                mapped_start_ns={WheelSide.LEFT: now_ns + 1_000_000},
                target_device_us={WheelSide.LEFT: 1_001_000},
                start_skew_ns=0,
            )
        )
        acceptance = {
            "case_id": "100hz-120s-0p5m",
            "cycle": 1,
            "operator_declared_distance_m": 0.5,
        }
        result = await service.handle_command(
            "start_record",
            {
                "sample_rate_hz": 100,
                "acceptance": acceptance,
            },
        )
        metadata = next(
            record.json_value
            for record in JournalReader(result["journal_path"]).iter_records()
            if record.kind is RecordKind.SESSION_META
        )
        assert metadata is not None
        assert metadata["acceptance"] == acceptance
        await service.close()

    asyncio.run(scenario())
