import asyncio
import struct
from pathlib import Path

from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.journal import (
    CENTER_JOURNAL_VERSION,
    JOURNAL_VERSION,
    JournalReader,
    JournalRecorder,
)
from tools.pc_acquisition.models import ImuSample, ReceivedSample, WheelSide
from tools.pc_acquisition.service import AcquisitionService, _parse_config, _parse_info, _side
from tools.pc_acquisition.transport import FakeBleTransport


def _sample(seq: int, t_us: int, base: int) -> bytes:
    return struct.pack(
        "<IIhhhhhh",
        seq & 0xFFFFFFFF,
        t_us & 0xFFFFFFFF,
        base,
        base + 1,
        base + 2,
        base + 3,
        base + 4,
        base + 5,
    )


def _batch(*samples: bytes) -> bytes:
    return bytes([len(samples)]) + b"".join(samples)


def _received(side: WheelSide, seq: int) -> ReceivedSample:
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
        arrival_ns=1_000_000_000 + seq,
        packet_id=seq,
        sequence_class="first" if seq == 0 else "contiguous",
    )


def test_center_role_byte_parses_in_info_config_and_command_side():
    info = (
        bytes([0x43, 1, 8, 0, 1, 3])
        + struct.pack("<ff", 4 / 32768, 2000 / 32768)
        + bytes([2, 1])
    )
    config = (
        b"WheelAthlete-XIAO-C".ljust(24, b"\x00")
        + bytes([0x43])
        + struct.pack("<H", 100)
        + bytes([1, 8, 0, 1])
    )
    assert _parse_info(info)["side"] == "C"
    assert _parse_config(config)["wheel"] == "C"
    assert _side("C") is WheelSide.CENTER
    assert _side("center") is WheelSide.CENTER


def test_l_r_journal_stays_v1_and_center_round_trips_in_v2(tmp_path: Path):
    lr = JournalRecorder(
        tmp_path,
        session_id="11111111-1111-1111-1111-111111111111",
        journal_version=JOURNAL_VERSION,
    )
    lr.submit_sample(_received(WheelSide.LEFT, 0))
    lr.submit_sample(_received(WheelSide.RIGHT, 1))
    lr_path = lr.finalize({"quality": "GOOD"})
    lr_samples = [record.sample for record in JournalReader(lr_path).read_all() if record.sample]
    assert [sample.side for sample in lr_samples] == [WheelSide.LEFT, WheelSide.RIGHT]

    center = JournalRecorder(
        tmp_path,
        session_id="22222222-2222-2222-2222-222222222222",
        journal_version=CENTER_JOURNAL_VERSION,
    )
    center.submit_sample(_received(WheelSide.LEFT, 0))
    center.submit_sample(_received(WheelSide.RIGHT, 0))
    center.submit_sample(_received(WheelSide.CENTER, 0))
    center_path = center.finalize({"quality": "GOOD"})
    center_samples = [
        record.sample for record in JournalReader(center_path).read_all() if record.sample
    ]
    assert [sample.side for sample in center_samples] == [
        WheelSide.LEFT,
        WheelSide.RIGHT,
        WheelSide.CENTER,
    ]


def test_fallback_summary_uses_journal_version_for_sensor_roles(tmp_path: Path):
    v1 = JournalRecorder(
        tmp_path,
        session_id="33333333-3333-3333-3333-333333333333",
        journal_version=JOURNAL_VERSION,
    )
    v1_path = v1.finalize({"quality": "GOOD"})

    v2 = JournalRecorder(
        tmp_path,
        session_id="44444444-4444-4444-4444-444444444444",
        journal_version=CENTER_JOURNAL_VERSION,
    )
    v2_path = v2.finalize({"quality": "GOOD"})

    service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
    assert service._fallback_session_summary(v1_path)["sample_counts"] == {
        "L": 0,
        "R": 0,
    }
    assert service._fallback_session_summary(v2_path)["sample_counts"] == {
        "L": 0,
        "R": 0,
        "C": 0,
    }


def test_engine_keeps_left_right_and_center_ingestion_independent():
    async def scenario():
        transport = FakeBleTransport()
        samples = []
        engine = DualBoardEngine(transport, queue_capacity=8, sample_sink=samples.append)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left-device")
        await engine.connect(WheelSide.RIGHT, "right-device")
        await engine.connect(WheelSide.CENTER, "center-device")
        transport.emit_imu("left-device", _batch(_sample(0, 100, 10)), arrival_ns=10)
        transport.emit_imu("right-device", _batch(_sample(0, 200, 20)), arrival_ns=20)
        transport.emit_imu("center-device", _batch(_sample(0, 300, 30)), arrival_ns=30)
        await engine.join()
        assert {item.side for item in samples} == {
            WheelSide.LEFT,
            WheelSide.RIGHT,
            WheelSide.CENTER,
        }
        for side in WheelSide:
            assert engine.metrics(side).samples_received == 1
            assert engine.metrics(side).sequence_gaps == 0
        await engine.stop()

    asyncio.run(scenario())
