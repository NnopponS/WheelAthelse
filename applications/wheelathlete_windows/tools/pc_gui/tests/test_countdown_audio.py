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


def test_countdown_shows_timing_5_4_3_2_1_without_hold_and_beeps(monkeypatch):
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
    state.recording_target_pc_ns = time.perf_counter_ns() + 10_000_000_000
    state.recording_started_utc_ms = time.time_ns() // 1_000_000 + 10_000
    acquisition.update_state(state)

    # 5 seconds initial state: displays '5', no 'hold', short beep
    assert acquisition.countdown_label.text() == "5"
    assert "hold" not in acquisition.countdown_label.text().lower()
    assert tones == [(700, 120)]

    # 4: displays '4', short beep
    acquisition._countdown_tick()
    assert acquisition.countdown_label.text() == "4"
    assert "hold" not in acquisition.countdown_label.text().lower()
    assert tones == [(700, 120), (700, 120)]

    # 3: displays '3', short beep
    acquisition._countdown_tick()
    assert acquisition.countdown_label.text() == "3"
    assert "hold" not in acquisition.countdown_label.text().lower()
    assert tones == [(700, 120), (700, 120), (700, 120)]

    # 2: displays '2', short beep
    acquisition._countdown_tick()
    assert acquisition.countdown_label.text() == "2"
    assert "hold" not in acquisition.countdown_label.text().lower()
    assert tones == [(700, 120), (700, 120), (700, 120), (700, 120)]

    # 1: displays '1', short beep
    acquisition._countdown_tick()
    assert acquisition.countdown_label.text() == "1"
    assert "hold" not in acquisition.countdown_label.text().lower()
    assert tones == [(700, 120), (700, 120), (700, 120), (700, 120), (700, 120)]

    # 0: triggers start cue with 'START!' and long start beep (1200, 500)
    acquisition._countdown_tick()
    assert acquisition.countdown_label.text() == "START!"
    assert tones[-1] == (1200, 500)

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_audio_wav_synthesis_and_worker():
    wav_bytes = main_window._make_tone_wav(700, 120)
    assert wav_bytes.startswith(b"RIFF")
    assert b"WAVE" in wav_bytes[:16]
    # Verify cached generation and prewarm dispatch without error
    main_window._play_tone(700, 120)
    main_window._prewarm_audio()
