import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays the countdown cue on the phone. Kept behind an interface so the BLE
/// countdown can be tested without invoking Android platform services.
abstract interface class CountdownCuePlayer {
  Future<void> play({required int durationMs, required bool isStart});
}

final class PlatformCountdownCuePlayer implements CountdownCuePlayer {
  const PlatformCountdownCuePlayer();

  static const _channel = MethodChannel('wheelathlete/countdown_cue');

  @override
  Future<void> play({required int durationMs, required bool isStart}) async {
    try {
      await _channel.invokeMethod<void>('play', {
        'durationMs': durationMs,
        'isStart': isStart,
      });
    } on MissingPluginException {
      // Desktop/test fallback. Android uses ToneGenerator in MainActivity.
      await SystemSound.play(SystemSoundType.click);
    }
  }
}

final countdownCuePlayerProvider = Provider<CountdownCuePlayer>(
  (ref) => const PlatformCountdownCuePlayer(),
);

/// A dual-wheel countdown emits the same cue from both boards. This guard
/// ensures the phone plays each cue once per countdown, not once per board.
final class CountdownCueDeduplicator {
  final Set<int> _played = <int>{};

  bool accept(int index) => _played.add(index);

  void reset() => _played.clear();
}
