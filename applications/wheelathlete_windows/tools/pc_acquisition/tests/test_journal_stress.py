import time
from pathlib import Path

from tools.pc_acquisition.journal import JournalReader, JournalRecorder, RecordKind
from tools.pc_acquisition.models import ImuSample, ReceivedSample, WheelSide


LOGICAL_DURATION_S = 30 * 60


def _sample(side: WheelSide, seq: int = 0) -> ReceivedSample:
    return ReceivedSample(
        side=side,
        sample=ImuSample(
            seq=seq,
            t_device_us=seq * 5_000,
            ax=1,
            ay=2,
            az=3,
            gx=4,
            gy=5,
            gz=6,
        ),
        arrival_ns=seq * 5_000_000,
        packet_id=seq // 12,
        sequence_class="first" if seq == 0 else "contiguous",
        missing_before=0,
    )


def test_journal_writer_handles_dual_200hz_30_min_equivalent(tmp_path: Path):
    recorder = JournalRecorder(
        tmp_path,
        session_id="99999999-8888-7777-6666-555555555555",
        queue_capacity=4096,
        fsync_every_records=4096,
    )
    recorder.append_metadata(
        {
            "sample_rate_hz": 200,
            "logical_duration_s": LOGICAL_DURATION_S,
            "stress_test": True,
        }
    )
    left = _sample(WheelSide.LEFT)
    right = _sample(WheelSide.RIGHT)
    samples_per_side = 200 * LOGICAL_DURATION_S
    total_samples = samples_per_side * 2
    started = time.perf_counter()

    for index in range(samples_per_side):
        assert recorder.submit_sample(left)
        assert recorder.submit_sample(right)
        if index % 512 == 511:
            recorder.wait_until_idle()
    recorder.wait_until_idle()
    wall_s = time.perf_counter() - started

    assert recorder.metrics.samples_written == total_samples
    assert recorder.metrics.queue_overflow_faults == 0
    assert recorder.fatal_fault is None
    assert recorder.metrics.queue_high_water <= 4096
    assert total_samples / max(wall_s, 1e-9) > 400

    final_path = recorder.finalize(
        {
            "quality": "GOOD",
            "logical_duration_s": LOGICAL_DURATION_S,
            "stress_test": True,
        }
    )
    validation = JournalReader(final_path).validate()
    assert validation.valid_records == total_samples + 2
    assert validation.finalized
    assert not validation.truncated_tail
    assert not validation.checksum_error


def test_slow_disk_backpressure_fails_closed_without_overwriting(tmp_path: Path):
    """A stalled writer may reject new samples but must never overwrite queued data."""

    recorder = JournalRecorder(
        tmp_path,
        session_id="11111111-2222-3333-4444-555555555555",
        queue_capacity=8,
        fsync_every_records=4096,
        start_thread=False,
    )
    original_append = recorder._append_record

    def slow_append(kind, payload, *, force_fsync=False):
        if kind is RecordKind.SAMPLE:
            time.sleep(0.01)
        return original_append(kind, payload, force_fsync=force_fsync)

    recorder._append_record = slow_append  # type: ignore[method-assign]
    recorder._start_thread()

    accepted = 0
    for seq in range(1_000):
        if not recorder.submit_sample(_sample(WheelSide.LEFT, seq)):
            break
        accepted += 1

    assert accepted > 0
    assert accepted < 1_000
    assert recorder.metrics.queue_overflow_faults == 1
    assert recorder.fatal_fault is not None
    assert recorder.fatal_fault.code == "journal_queue_overflow"

    # Everything accepted before the fail-closed boundary must still reach disk.
    recorder.wait_until_idle()
    assert recorder.metrics.samples_written == accepted
    recorder.abort_without_finalize_for_test()

    validation = JournalReader(recorder.open_path).validate()
    assert validation.valid_records == accepted
    assert not validation.truncated_tail
    assert not validation.checksum_error


def test_disk_write_exception_sets_fatal_fault_and_keeps_journal_structurally_valid(
    tmp_path: Path,
):
    recorder = JournalRecorder(
        tmp_path,
        session_id="aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb",
        queue_capacity=8,
        fsync_every_records=4096,
        start_thread=False,
    )
    original_append = recorder._append_record
    fail_next_sample = True

    def failing_append(kind, payload, *, force_fsync=False):
        nonlocal fail_next_sample
        if kind is RecordKind.SAMPLE and fail_next_sample:
            fail_next_sample = False
            raise OSError("simulated disk write failure")
        return original_append(kind, payload, force_fsync=force_fsync)

    recorder._append_record = failing_append  # type: ignore[method-assign]
    recorder._start_thread()
    assert recorder.submit_sample(_sample(WheelSide.LEFT, 0))
    assert recorder.submit_sample(_sample(WheelSide.LEFT, 1))
    recorder.wait_until_idle()

    assert recorder.fatal_fault is not None
    assert recorder.fatal_fault.code == "journal_write_failure"
    assert "simulated disk write failure" in recorder.fatal_fault.message
    assert recorder.metrics.samples_written == 1
    recorder.abort_without_finalize_for_test()

    validation = JournalReader(recorder.open_path).validate()
    assert validation.valid_records == 1
    assert not validation.truncated_tail
    assert not validation.checksum_error

