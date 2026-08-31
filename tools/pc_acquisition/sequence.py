from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from enum import Enum


UINT32_MASK = 0xFFFFFFFF
UINT32_HALF = 0x80000000


class SequenceClass(str, Enum):
    FIRST = "first"
    CONTIGUOUS = "contiguous"
    GAP = "gap"
    DUPLICATE = "duplicate"
    OUT_OF_ORDER = "out_of_order"


@dataclass(frozen=True, slots=True)
class SequenceObservation:
    classification: SequenceClass
    missing: int = 0


class SequenceTracker:
    """Wrap-aware sequence classifier with bounded duplicate memory."""

    def __init__(self, recent_window: int = 512) -> None:
        if recent_window < 1:
            raise ValueError("recent_window must be >= 1")
        self._last: int | None = None
        self._recent_order: deque[int] = deque(maxlen=recent_window)
        self._recent: set[int] = set()

    def _remember(self, seq: int) -> None:
        if len(self._recent_order) == self._recent_order.maxlen:
            evicted = self._recent_order[0]
            self._recent.discard(evicted)
        self._recent_order.append(seq)
        self._recent.add(seq)

    def observe(self, seq: int) -> SequenceObservation:
        seq &= UINT32_MASK
        if self._last is None:
            self._last = seq
            self._remember(seq)
            return SequenceObservation(SequenceClass.FIRST)

        if seq in self._recent:
            return SequenceObservation(SequenceClass.DUPLICATE)

        expected = (self._last + 1) & UINT32_MASK
        if seq == expected:
            self._last = seq
            self._remember(seq)
            return SequenceObservation(SequenceClass.CONTIGUOUS)

        forward = (seq - expected) & UINT32_MASK
        if 0 < forward < UINT32_HALF:
            self._last = seq
            self._remember(seq)
            return SequenceObservation(SequenceClass.GAP, missing=forward)

        # A value behind the expected point is a late/out-of-order sample.  It
        # does not move the authoritative sequence cursor backwards.
        self._remember(seq)
        return SequenceObservation(SequenceClass.OUT_OF_ORDER)
