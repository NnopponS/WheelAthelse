import struct
from pathlib import Path


HEADER = Path(__file__).parents[1] / 'src' / 'ble_types.h'


def test_protocol_161_health_layout_and_event_ids():
    source = HEADER.read_text()
    assert 'AcqHealth    = 0x60' in source
    assert 'ReplayResult = 0x61' in source
    assert 'ACQ_HEALTH_SIZE    = 28' in source
    assert 'packAcqHealth' in source
    payload = struct.pack('<BBIIIIHII', 0x60, 2, 10, 9, 1, 2, 3, 0, 0)
    assert len(payload) == 28


def test_produced_count_includes_samples_lost_before_queueing():
    source = (Path(__file__).parents[1] / 'src' / 'ble_service.cpp').read_text()
    assert 'imu().sampleCount() + imu().queueDropCount()' in source


def test_xiao_reports_queue_drops_and_zero_fifo_faults_separately():
    root = Path(__file__).parents[1] / 'src'
    header = (root / 'imu_reader.h').read_text()
    source = (root / 'ble_service.cpp').read_text()
    assert 'queueDropCount()' in header
    assert 'fifoDroppedSampleCount()' in header
    assert 'imu().queueDropCount()' in source
    assert 'imu().fifoOverflowCount()' in source
    assert 'imu().fifoDroppedSampleCount()' in source
