import csv
import os
from pathlib import Path

from tools.pc_acquisition.journal import (
    JournalReader,
    JournalRecorder,
    RecordKind,
    recover_open_journal,
)
from tools.pc_acquisition.models import IngestionMetrics, ImuSample, ReceivedSample, WheelSide
from tools.pc_acquisition.qc import BoardQcInput, QualityLevel, SessionQcInput, evaluate_session_qc
from tools.pc_acquisition.sync_protocol import AcqHealthEvent


def _received(side: WheelSide, seq: int, arrival_ns: int = 1_000_000_000) -> ReceivedSample:
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
        arrival_ns=arrival_ns,
        packet_id=seq // 10,
        sequence_class="contiguous" if seq else "first",
        missing_before=0,
    )


def test_journal_round_trip_finalizes_atomically_and_csv_is_derived(tmp_path: Path):
    recorder = JournalRecorder(tmp_path, session_id="12345678-1234-5678-1234-567812345678")
    recorder.append_metadata({"athlete": "A", "sample_rate_hz": 100})
    recorder.submit_sample(_received(WheelSide.LEFT, 0))
    recorder.submit_sample(_received(WheelSide.RIGHT, 0, 1_000_100_000))
    recorder.wait_until_idle()

    final_path = recorder.finalize({"quality": "GOOD"})
    assert final_path.suffix == ".waj"
    assert final_path.exists()
    assert not final_path.with_suffix(".open").exists()

    reader = JournalReader(final_path)
    records = reader.read_all()
    assert [record.kind for record in records] == [
        RecordKind.SESSION_META,
        RecordKind.SAMPLE,
        RecordKind.SAMPLE,
        RecordKind.FINALIZE,
    ]
    samples = [record.sample for record in records if record.kind is RecordKind.SAMPLE]
    assert [(s.side, s.sample.seq, s.arrival_ns) for s in samples] == [
        (WheelSide.LEFT, 0, 1_000_000_000),
        (WheelSide.RIGHT, 0, 1_000_100_000),
    ]

    csv_path = tmp_path / "derived.csv"
    reader.export_csv(csv_path)
    with csv_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 2
    assert rows[0]["session_id"] == "12345678-1234-5678-1234-567812345678"
    assert rows[0]["wheel"] == "L"
    assert rows[1]["wheel"] == "R"


def test_recovery_keeps_original_open_file_and_salvages_only_checksum_valid_prefix(tmp_path: Path):
    recorder = JournalRecorder(
        tmp_path,
        session_id="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        fsync_every_records=1,
    )
    recorder.append_metadata({"sample_rate_hz": 100})
    recorder.submit_sample(_received(WheelSide.LEFT, 0))
    recorder.wait_until_idle()
    open_path = recorder.open_path
    recorder.abort_without_finalize_for_test()

    # Simulate a crash during the next frame: complete records stay intact but
    # an arbitrary partial tail must never be interpreted as a sample.
    with open_path.open("ab") as handle:
        handle.write(b"\x02\x40\x00")
        handle.flush()
        os.fsync(handle.fileno())

    report = JournalReader(open_path).validate()
    assert report.valid_records == 2
    assert report.truncated_tail
    assert not report.finalized

    recovered = recover_open_journal(open_path)
    assert open_path.exists()  # preserve forensic original
    assert recovered.exists()
    recovered_report = JournalReader(recovered).validate()
    assert recovered_report.valid_records == 2
    assert not recovered_report.truncated_tail


def test_journal_writer_queue_overflow_is_fatal_and_never_overwrites(tmp_path: Path):
    recorder = JournalRecorder(
        tmp_path,
        session_id="00000000-0000-0000-0000-000000000001",
        queue_capacity=2,
        start_thread=False,
    )
    assert recorder.submit_sample(_received(WheelSide.LEFT, 0))
    assert recorder.submit_sample(_received(WheelSide.LEFT, 1))
    assert not recorder.submit_sample(_received(WheelSide.LEFT, 2))
    assert recorder.metrics.queue_high_water == 2
    assert recorder.metrics.queue_overflow_faults == 1
    assert recorder.fatal_fault is not None
    recorder.abort_without_finalize_for_test()


def _health(count: int, *, queue_drops=0, failures=0, fifo_drops=0) -> AcqHealthEvent:
    return AcqHealthEvent(
        state=0,
        produced=count,
        notified=count,
        queue_drops=queue_drops,
        transport_failures=failures,
        queue_depth=0,
        fifo_faults=0,
        fifo_dropped_samples=fifo_drops,
    )


def _board(side: WheelSide, *, count=1000, metrics=None, health=None) -> BoardQcInput:
    metrics = metrics or IngestionMetrics(samples_received=count)
    return BoardQcInput(
        side=side,
        configured_rate_hz=100,
        duration_s=10.0,
        host_metrics=metrics,
        firmware_health=health or _health(count),
        start_acknowledged=True,
        stop_acknowledged=True,
    )


def test_qc_good_warning_degraded_and_invalid_are_reasoned_not_rssi_based():
    good = evaluate_session_qc(
        SessionQcInput(
            boards=(_board(WheelSide.LEFT), _board(WheelSide.RIGHT)),
            start_skew_ns=2_000_000,
            journal_queue_overflow=0,
        )
    )
    assert good.level is QualityLevel.GOOD
    assert not good.reasons

    warning_health = _health(1000, failures=1)
    warning = evaluate_session_qc(
        SessionQcInput(
            boards=(
                _board(WheelSide.LEFT, health=warning_health),
                _board(WheelSide.RIGHT),
            ),
            start_skew_ns=2_000_000,
        )
    )
    assert warning.level is QualityLevel.WARNING
    assert "transport_retry" in {reason.code for reason in warning.reasons}

    no_health = _board(WheelSide.LEFT, health=_health(1000))
    no_health = BoardQcInput(
        side=no_health.side,
        configured_rate_hz=no_health.configured_rate_hz,
        duration_s=no_health.duration_s,
        host_metrics=no_health.host_metrics,
        firmware_health=None,
        start_acknowledged=True,
        stop_acknowledged=True,
    )
    degraded = evaluate_session_qc(
        SessionQcInput(boards=(no_health,), start_skew_ns=None)
    )
    assert degraded.level is QualityLevel.DEGRADED
    assert {reason.code for reason in degraded.reasons} >= {
        "missing_final_health",
        "missing_start_skew",
    }

    bad_metrics = IngestionMetrics(samples_received=998, sequence_gaps=2)
    invalid = evaluate_session_qc(
        SessionQcInput(
            boards=(
                _board(
                    WheelSide.LEFT,
                    count=998,
                    metrics=bad_metrics,
                    health=AcqHealthEvent(
                        state=0,
                        produced=1000,
                        notified=1000,
                        queue_drops=0,
                        transport_failures=0,
                        queue_depth=0,
                        fifo_faults=0,
                        fifo_dropped_samples=0,
                    ),
                ),
            ),
            start_skew_ns=1_000_000,
            journal_queue_overflow=1,
        )
    )
    assert invalid.level is QualityLevel.INVALID
    codes = {reason.code for reason in invalid.reasons}
    assert "sequence_gap" in codes
    assert "count_mismatch" in codes
    assert "journal_queue_overflow" in codes


def test_qc_invalid_when_authoritative_journal_is_incomplete_or_writer_faulted():
    result = evaluate_session_qc(
        SessionQcInput(
            boards=(_board(WheelSide.LEFT, count=1000),),
            start_skew_ns=0,
            journal_samples_written=999,
            journal_fault_code="journal_write_failure",
            journal_fault_message="simulated disk failure",
        )
    )
    assert result.level is QualityLevel.INVALID
    codes = {reason.code for reason in result.reasons}
    assert "journal_writer_fault" in codes
    assert "journal_count_mismatch" in codes

