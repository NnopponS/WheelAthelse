from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum

from .models import IngestionMetrics, WheelSide
from .sync_protocol import AcqHealthEvent


class QualityLevel(IntEnum):
    GOOD = 0
    WARNING = 1
    DEGRADED = 2
    INVALID = 3


@dataclass(frozen=True, slots=True)
class QcReason:
    code: str
    level: QualityLevel
    detail: str
    side: WheelSide | None = None


@dataclass(frozen=True, slots=True)
class BoardQcInput:
    side: WheelSide
    configured_rate_hz: int
    duration_s: float
    host_metrics: IngestionMetrics
    firmware_health: AcqHealthEvent | None
    start_acknowledged: bool
    stop_acknowledged: bool


@dataclass(frozen=True, slots=True)
class SessionQcInput:
    boards: tuple[BoardQcInput, ...]
    start_skew_ns: int | None
    journal_queue_overflow: int = 0
    journal_samples_written: int | None = None
    journal_fault_code: str | None = None
    journal_fault_message: str | None = None


@dataclass(frozen=True, slots=True)
class SessionQcResult:
    level: QualityLevel
    reasons: tuple[QcReason, ...]


def evaluate_session_qc(value: SessionQcInput) -> SessionQcResult:
    reasons: list[QcReason] = []

    def add(code: str, level: QualityLevel, detail: str, side: WheelSide | None = None) -> None:
        reasons.append(QcReason(code=code, level=level, detail=detail, side=side))

    if value.journal_queue_overflow > 0:
        add(
            "journal_queue_overflow",
            QualityLevel.INVALID,
            f"journal writer overflowed {value.journal_queue_overflow} time(s)",
        )

    if value.journal_fault_code is not None:
        detail = value.journal_fault_code
        if value.journal_fault_message:
            detail = f"{detail}: {value.journal_fault_message}"
        add(
            "journal_writer_fault",
            QualityLevel.INVALID,
            detail,
        )

    if value.journal_samples_written is not None:
        expected_samples = sum(
            board.host_metrics.samples_received for board in value.boards
        )
        if value.journal_samples_written != expected_samples:
            add(
                "journal_count_mismatch",
                QualityLevel.INVALID,
                "authoritative journal/host counts differ: "
                f"written={value.journal_samples_written}, "
                f"received={expected_samples}",
            )

    for board in value.boards:
        metrics = board.host_metrics
        side = board.side
        if metrics.queue_overflow_faults > 0:
            add(
                "host_queue_overflow",
                QualityLevel.INVALID,
                f"host ingestion queue overflowed {metrics.queue_overflow_faults} time(s)",
                side,
            )
        if metrics.malformed_packets > 0:
            add(
                "malformed_packet",
                QualityLevel.INVALID,
                f"host rejected {metrics.malformed_packets} malformed packet(s)",
                side,
            )
        if metrics.sequence_gaps > 0:
            add(
                "sequence_gap",
                QualityLevel.INVALID,
                f"{metrics.sequence_gaps} sample sequence value(s) missing",
                side,
            )
        if metrics.out_of_order_samples > 0:
            add(
                "out_of_order",
                QualityLevel.INVALID,
                f"{metrics.out_of_order_samples} out-of-order sample(s)",
                side,
            )
        if metrics.duplicate_samples > 0:
            add(
                "duplicate_sample",
                QualityLevel.WARNING,
                f"{metrics.duplicate_samples} duplicate sample(s) observed",
                side,
            )

        health = board.firmware_health
        if health is None:
            add(
                "missing_final_health",
                QualityLevel.DEGRADED,
                "final firmware ACQ_HEALTH was not confirmed",
                side,
            )
        else:
            if health.queue_drops > 0:
                add(
                    "firmware_queue_drop",
                    QualityLevel.INVALID,
                    f"firmware sample queue dropped {health.queue_drops} sample(s)",
                    side,
                )
            if health.fifo_faults > 0 or health.fifo_dropped_samples > 0:
                add(
                    "imu_fifo_loss",
                    QualityLevel.INVALID,
                    f"IMU FIFO faults={health.fifo_faults}, lost={health.fifo_dropped_samples}",
                    side,
                )
            if not (
                health.produced == health.notified == metrics.samples_received
            ):
                add(
                    "count_mismatch",
                    QualityLevel.INVALID,
                    "firmware/host counts differ: "
                    f"produced={health.produced}, notified={health.notified}, "
                    f"received={metrics.samples_received}",
                    side,
                )
            if health.transport_failures > 0:
                add(
                    "transport_retry",
                    QualityLevel.WARNING,
                    f"firmware reported {health.transport_failures} BLE transport failure(s)",
                    side,
                )

        if not board.start_acknowledged:
            add(
                "missing_start_ack",
                QualityLevel.DEGRADED,
                "START_FIRED was not confirmed",
                side,
            )
        if not board.stop_acknowledged:
            add(
                "missing_stop_ack",
                QualityLevel.DEGRADED,
                "STOP_FIRED was not confirmed",
                side,
            )

        if board.duration_s <= 0:
            add(
                "invalid_duration",
                QualityLevel.DEGRADED,
                "recording duration is not positive",
                side,
            )
        elif board.configured_rate_hz > 0:
            effective_rate = metrics.samples_received / board.duration_s
            error_fraction = abs(effective_rate - board.configured_rate_hz) / board.configured_rate_hz
            if error_fraction > 0.10:
                add(
                    "effective_rate_out_of_range",
                    QualityLevel.DEGRADED,
                    f"effective rate {effective_rate:.3f} Hz differs by more than 10%",
                    side,
                )
            elif error_fraction > 0.05:
                add(
                    "effective_rate_warning",
                    QualityLevel.WARNING,
                    f"effective rate {effective_rate:.3f} Hz differs by more than 5%",
                    side,
                )

    if value.start_skew_ns is None:
        add(
            "missing_start_skew",
            QualityLevel.DEGRADED,
            "Left/Right synchronized start skew is unavailable",
        )
    elif len(value.boards) >= 2:
        highest_rate = max(board.configured_rate_hz for board in value.boards)
        if highest_rate > 0:
            sample_period_ns = 1_000_000_000 / highest_rate
            if value.start_skew_ns >= sample_period_ns:
                add(
                    "start_skew_exceeds_sample",
                    QualityLevel.DEGRADED,
                    f"start skew {value.start_skew_ns / 1e6:.3f} ms exceeds one sample period",
                )

    level = max((reason.level for reason in reasons), default=QualityLevel.GOOD)
    return SessionQcResult(level=level, reasons=tuple(reasons))
