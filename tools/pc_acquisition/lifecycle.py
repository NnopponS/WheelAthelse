from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import Callable, Iterable

from .clock_sync import ClockModel, ClockObservation, Uint32Unwrapper
from .control import scheduled_start, stop, sync_ping
from .engine import DualBoardEngine
from .models import NotificationEnvelope, WheelSide
from .sync_protocol import (
    AcqHealthEvent,
    CmdNackEvent,
    StartFiredEvent,
    StopFiredEvent,
    SyncResponseEvent,
    parse_sync_event,
)
from .transport import BleTransport
from .uuids import CONTROL_UUID


class LifecycleError(RuntimeError):
    pass


@dataclass(slots=True)
class _PendingPing:
    t1_ns: int
    future: asyncio.Future[ClockObservation]


@dataclass(slots=True)
class _BoardState:
    unwrapper: Uint32Unwrapper = field(default_factory=Uint32Unwrapper)
    observations: list[ClockObservation] = field(default_factory=list)
    clock_model: ClockModel | None = None
    pending_pings: dict[int, _PendingPing] = field(default_factory=dict)
    start_waiter: asyncio.Future[StartFiredEvent] | None = None
    stop_waiter: asyncio.Future[StopFiredEvent] | None = None
    last_health: AcqHealthEvent | None = None
    last_nack: CmdNackEvent | None = None


@dataclass(frozen=True, slots=True)
class StartResult:
    pc_start_ns: int
    acknowledged: frozenset[WheelSide]
    mapped_start_ns: dict[WheelSide, int]
    target_device_us: dict[WheelSide, int]
    start_skew_ns: int | None


@dataclass(frozen=True, slots=True)
class StopResult:
    acknowledged: bool
    write_attempts: int
    event: StopFiredEvent | None
    health: AcqHealthEvent | None
    error: str | None = None


class SyncLifecycleController:
    """PC-master synchronization and deterministic dual-board lifecycle."""

    def __init__(self, engine: DualBoardEngine, transport: BleTransport) -> None:
        self.engine = engine
        self.transport = transport
        self._state = {side: _BoardState() for side in WheelSide}
        self._next_ping_token = 1
        self.engine.set_sync_sink(self._on_sync_envelope)

    def install_clock_model(self, side: WheelSide, model: ClockModel) -> None:
        self._state[side].clock_model = model

    def clock_model(self, side: WheelSide) -> ClockModel | None:
        return self._state[side].clock_model

    def health(self, side: WheelSide) -> AcqHealthEvent | None:
        return self._state[side].last_health

    async def synchronize(
        self,
        side: WheelSide,
        *,
        count: int = 10,
        timeout_s: float = 1.0,
        inter_ping_s: float = 0.01,
        clock_ns: Callable[[], int] = time.monotonic_ns,
    ) -> ClockModel:
        if count < 1:
            raise ValueError("count must be >= 1")
        device_id = self._require_device(side)
        state = self._state[side]
        new_observations: list[ClockObservation] = []
        for index in range(count):
            token = self._next_ping_token & 0xFFFFFFFF
            self._next_ping_token += 1
            loop = asyncio.get_running_loop()
            future: asyncio.Future[ClockObservation] = loop.create_future()
            t1_ns = int(clock_ns())
            state.pending_pings[token] = _PendingPing(t1_ns=t1_ns, future=future)
            try:
                await self.transport.write(
                    device_id, CONTROL_UUID, sync_ping(token), response=True
                )
                observation = await asyncio.wait_for(future, timeout=timeout_s)
            except BaseException:
                state.pending_pings.pop(token, None)
                if not future.done():
                    future.cancel()
                raise
            new_observations.append(observation)
            if index + 1 < count and inter_ping_s > 0:
                await asyncio.sleep(inter_ping_s)

        state.observations.extend(new_observations)
        state.clock_model = ClockModel.fit(state.observations)
        return state.clock_model

    async def scheduled_start(
        self,
        sides: Iterable[WheelSide],
        *,
        pc_start_ns: int | None = None,
        lead_time_s: float = 3.0,
        ack_timeout_s: float = 1.0,
    ) -> StartResult:
        selected = tuple(sides)
        if not selected:
            raise ValueError("at least one wheel is required")
        if pc_start_ns is None:
            pc_start_ns = time.monotonic_ns() + round(lead_time_s * 1_000_000_000)

        targets: dict[WheelSide, int] = {}
        waiters: dict[WheelSide, asyncio.Future[StartFiredEvent]] = {}
        loop = asyncio.get_running_loop()
        for side in selected:
            model = self._require_model(side)
            targets[side] = model.pc_to_device_us(pc_start_ns) & 0xFFFFFFFF
            waiter: asyncio.Future[StartFiredEvent] = loop.create_future()
            self._state[side].start_waiter = waiter
            waiters[side] = waiter

        # Commands may arrive at different host times; device-local scheduled
        # targets are derived from the same PC T0 so write ordering is not the
        # synchronization mechanism.
        for side in selected:
            await self.transport.write(
                self._require_device(side),
                CONTROL_UUID,
                scheduled_start(targets[side]),
                response=True,
            )

        mapped: dict[WheelSide, int] = {}
        acknowledged: set[WheelSide] = set()
        for side in selected:
            try:
                event = await asyncio.wait_for(
                    asyncio.shield(waiters[side]), timeout=ack_timeout_s
                )
            except TimeoutError as exc:
                raise LifecycleError(f"START_FIRED timeout for {side.value}") from exc
            unwrapped = self._state[side].unwrapper.unwrap(event.t_device_us)
            mapped[side] = self._require_model(side).device_to_pc_ns(unwrapped)
            acknowledged.add(side)

        skew = max(mapped.values()) - min(mapped.values()) if len(mapped) >= 2 else 0
        return StartResult(
            pc_start_ns=pc_start_ns,
            acknowledged=frozenset(acknowledged),
            mapped_start_ns=mapped,
            target_device_us=targets,
            start_skew_ns=skew,
        )

    async def stop_all(
        self,
        sides: Iterable[WheelSide],
        *,
        max_attempts: int = 3,
        retry_delay_s: float = 0.1,
        ack_timeout_s: float = 1.5,
    ) -> dict[WheelSide, StopResult]:
        if max_attempts < 1:
            raise ValueError("max_attempts must be >= 1")
        selected = tuple(sides)
        loop = asyncio.get_running_loop()
        waiters: dict[WheelSide, asyncio.Future[StopFiredEvent]] = {}
        attempts_by_side: dict[WheelSide, int] = {}
        write_succeeded: dict[WheelSide, bool] = {side: False for side in selected}
        write_errors: dict[WheelSide, str] = {}
        for side in selected:
            waiter: asyncio.Future[StopFiredEvent] = loop.create_future()
            self._state[side].stop_waiter = waiter
            waiters[side] = waiter

        # Serialize writes across peripherals to avoid host resource pressure.
        # ACKs are awaited only after every STOP write has had its bounded retry
        # opportunity, so one slow wheel never delays issuing STOP to the other.
        for side in selected:
            device_id = self._require_device(side)
            for attempt in range(1, max_attempts + 1):
                attempts_by_side[side] = attempt
                try:
                    await self.transport.write(
                        device_id, CONTROL_UUID, stop(), response=True
                    )
                    write_succeeded[side] = True
                    write_errors.pop(side, None)
                    break
                except Exception as exc:  # transport errors are retryable here
                    write_errors[side] = str(exc)
                    if attempt < max_attempts and retry_delay_s > 0:
                        await asyncio.sleep(retry_delay_s * attempt)
            if not write_succeeded[side]:
                # Disconnect is the firmware failsafe: its disconnect handler
                # stops acquisition.  Use the engine path so local connection
                # ownership is cleared as well.
                await self.engine.disconnect(side)

        results: dict[WheelSide, StopResult] = {}
        for side in selected:
            if not write_succeeded[side]:
                results[side] = StopResult(
                    acknowledged=False,
                    write_attempts=attempts_by_side[side],
                    event=None,
                    health=self._state[side].last_health,
                    error=write_errors.get(side, "STOP write failed"),
                )
                continue
            try:
                event = await asyncio.wait_for(
                    asyncio.shield(waiters[side]), timeout=ack_timeout_s
                )
                results[side] = StopResult(
                    acknowledged=True,
                    write_attempts=attempts_by_side[side],
                    event=event,
                    health=self._state[side].last_health,
                )
            except TimeoutError:
                # A written STOP without STOP_FIRED cannot be assumed complete.
                # Disconnect to force the firmware stop handler and fail closed.
                await self.engine.disconnect(side)
                results[side] = StopResult(
                    acknowledged=False,
                    write_attempts=attempts_by_side[side],
                    event=None,
                    health=self._state[side].last_health,
                    error="STOP_FIRED timeout",
                )
        return results

    def _on_sync_envelope(self, side: WheelSide, envelope: NotificationEnvelope) -> None:
        event = parse_sync_event(envelope.payload)
        state = self._state[side]
        if isinstance(event, SyncResponseEvent):
            pending = state.pending_pings.pop(event.t_app_ms, None)
            if pending is None or pending.future.done():
                return
            device_us = state.unwrapper.unwrap(event.t_device_us)
            t3_ns = envelope.arrival_ns
            rtt_ns = max(0, t3_ns - pending.t1_ns)
            observation = ClockObservation(
                device_us=device_us,
                pc_midpoint_ns=pending.t1_ns + rtt_ns // 2,
                rtt_ns=rtt_ns,
            )
            pending.future.set_result(observation)
            return
        if isinstance(event, StartFiredEvent):
            waiter = state.start_waiter
            if waiter is not None and not waiter.done():
                waiter.set_result(event)
            return
        if isinstance(event, StopFiredEvent):
            waiter = state.stop_waiter
            if waiter is not None and not waiter.done():
                waiter.set_result(event)
            return
        if isinstance(event, AcqHealthEvent):
            state.last_health = event
            return
        if isinstance(event, CmdNackEvent):
            state.last_nack = event

    def _require_device(self, side: WheelSide) -> str:
        device_id = self.engine.device_id(side)
        if device_id is None:
            raise LifecycleError(f"{side.value} wheel is not connected")
        return device_id

    def _require_model(self, side: WheelSide) -> ClockModel:
        model = self._state[side].clock_model
        if model is None:
            raise LifecycleError(f"{side.value} wheel has no clock model")
        return model
