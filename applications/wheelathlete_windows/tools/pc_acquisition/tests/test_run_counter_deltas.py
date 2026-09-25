from tools.pc_acquisition.models import IngestionMetrics
from tools.pc_acquisition.service import _firmware_health_delta, _metrics_delta


def test_host_integrity_counters_are_scoped_to_the_current_recording():
    baseline = IngestionMetrics(
        notifications_received=100,
        samples_received=200,
        malformed_packets=8,
        sequence_gaps=4,
        duplicate_samples=2,
        out_of_order_samples=1,
        queue_overflow_faults=2,
    )
    current = IngestionMetrics(
        notifications_received=110,
        samples_received=225,
        malformed_packets=9,
        sequence_gaps=7,
        duplicate_samples=3,
        out_of_order_samples=1,
        queue_overflow_faults=5,
    )

    delta = _metrics_delta(current, baseline)

    assert delta.notifications_received == 10
    assert delta.samples_received == 25
    assert delta.malformed_packets == 1
    assert delta.sequence_gaps == 3
    assert delta.duplicate_samples == 1
    assert delta.out_of_order_samples == 0
    assert delta.queue_overflow_faults == 3


def test_firmware_queue_and_fifo_faults_are_deltas_but_depth_is_current():
    before = {
        "produced": 100,
        "notified": 90,
        "queue_drops": 3,
        "transport_failures": 1,
        "queue_depth": 5,
        "fifo_faults": 2,
        "fifo_dropped_samples": 10,
        "state": 1,
    }
    after = {
        "produced": 110,
        "notified": 98,
        "queue_drops": 4,
        "transport_failures": 2,
        "queue_depth": 1,
        "fifo_faults": 3,
        "fifo_dropped_samples": 15,
        "state": 1,
    }

    delta = _firmware_health_delta(after, before)

    assert delta == {
        "produced": 10,
        "notified": 8,
        "queue_drops": 1,
        "transport_failures": 1,
        "queue_depth": 1,
        "fifo_faults": 1,
        "fifo_dropped_samples": 5,
        "state": 1,
    }
