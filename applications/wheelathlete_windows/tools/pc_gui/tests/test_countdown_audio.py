import os
import time

from PySide6.QtCore import QEventLoop, QTimer
from PySide6.QtWidgets import QApplication

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from tools.pc_gui.controller import DemoController
import tools.pc_gui.main_window as main_window
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


def _wait(ms: int) -> None:
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def test_final_start_cue_survives_recording_state_race(monkeypatch):
    tones: list[tuple[int, int]] = []
    monkeypatch.setattr(
        main_window, "_play_tone", lambda frequency, duration: tones.append((frequency, duration))
    )

    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    acquisition = window.acquisition
    state = controller.state
    state.recording = False
    state.recording_starting = True
    state.countdown = 5
    state.recording_target_pc_ns = time.perf_counter_ns() + 50_000_000
    state.recording_started_utc_ms = time.time_ns() // 1_000_000 + 50
    acquisition.update_state(state)
    assert tones == [(700, 120)]

    # Simulate the daemon's recording event winning the race against the
    # visual countdown timer.  The independent T0 timer must remain armed.
    state.recording = True
    state.recording_starting = False
    state.countdown = None
    acquisition.update_state(state)
    _wait(120)

    assert tones.count((1200, 500)) == 1

    # A late/fallback countdown tick must not duplicate the start cue.
    acquisition._countdown_remaining = 1
    acquisition._countdown_tick()
    assert tones.count((1200, 500)) == 1

    controller.stop_record()
    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_cancelled_countdown_cancels_pending_start_cue(monkeypatch):
    tones: list[tuple[int, int]] = []
    monkeypatch.setattr(
        main_window, "_play_tone", lambda frequency, duration: tones.append((frequency, duration))
    )

    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    acquisition = window.acquisition
    state = controller.state
    state.recording = False
    state.recording_starting = True
    state.countdown = 5
    state.recording_target_pc_ns = time.perf_counter_ns() + 80_000_000
    state.recording_started_utc_ms = time.time_ns() // 1_000_000 + 80
    acquisition.update_state(state)

    state.recording_starting = False
    state.countdown = None
    state.recording_target_pc_ns = None
    state.recording_started_utc_ms = None
    acquisition.update_state(state)
    _wait(140)

    assert (1200, 500) not in tones

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()
