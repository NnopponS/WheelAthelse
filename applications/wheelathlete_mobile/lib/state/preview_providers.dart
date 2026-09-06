import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/session_stats.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Identifies which wheel(s) the preview chart should display.
enum PreviewWheelSelection { left, right, both }

/// Sealed source for the preview page. Either a session on disk (Browse tap)
/// or an in-memory session (stopped view, samples still in RecordingNotifier).
sealed class PreviewSource {
  const PreviewSource();
}

/// Disk-backed source: loads meta + sample chunks from [StorageRepository].
class DiskPreviewSource extends PreviewSource {
  const DiskPreviewSource({
    required this.topic,
    required this.trialNumber,
    required this.sessionId,
  });

  final String topic;
  final int trialNumber;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is DiskPreviewSource &&
      other.topic == topic &&
      other.trialNumber == trialNumber &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(topic, trialNumber, sessionId);
}

/// In-memory source: meta + samples already loaded (stopped view case).
class InMemoryPreviewSource extends PreviewSource {
  const InMemoryPreviewSource({required this.meta, required this.samples});

  final SessionMeta meta;
  final List<BufferedSample> samples;

  @override
  bool operator ==(Object other) =>
      other is InMemoryPreviewSource &&
      other.meta.sessionId == meta.sessionId &&
      identical(other.samples, samples);

  @override
  int get hashCode => Object.hash(meta.sessionId, identityHashCode(samples));
}

/// Immutable state for the preview page.
class PreviewState {
  const PreviewState({
    required this.meta,
    required this.totalSampleCount,
    this.stats,
    this.currentChunk = const [],
    this.scrubPositionMs = 0,
    this.selectedWheel = PreviewWheelSelection.both,
    this.isLoading = false,
    this.error,
  });

  final SessionMeta meta;
  final int totalSampleCount;
  final SessionStats? stats;
  final List<BufferedSample> currentChunk;
  final int scrubPositionMs;
  final PreviewWheelSelection selectedWheel;
  final bool isLoading;
  final String? error;

  PreviewState copyWith({
    SessionStats? stats,
    List<BufferedSample>? currentChunk,
    int? scrubPositionMs,
    PreviewWheelSelection? selectedWheel,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PreviewState(
      meta: meta,
      totalSampleCount: totalSampleCount,
      stats: stats ?? this.stats,
      currentChunk: currentChunk ?? this.currentChunk,
      scrubPositionMs: scrubPositionMs ?? this.scrubPositionMs,
      selectedWheel: selectedWheel ?? this.selectedWheel,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Size of each chunk loaded from disk for the chart window.
const _kChunkSize = 500;

/// Half-window in samples around the scrub position. The chunk loaded is
/// `[center - _kHalfWindow, center + _kHalfWindow)` clamped to [0, total].
const _kHalfWindow = 250;

/// Debounce window for scrub-driven chunk loads (ms).
const _kScrubDebounceMs = 200;

/// Notifier that drives the session preview page: loads meta + the first
/// chunk on build, computes [SessionStats], and re-loads a chunk around the
/// scrub position when the user scrubs (debounced).
///
/// Constructed per [PreviewSource] via [previewControllerProvider].
class PreviewController extends Notifier<PreviewState> {
  PreviewController(this.source);

  final PreviewSource source;
  Timer? _scrubTimer;

  @override
  PreviewState build() {
    // Async load — return a loading shell first, then fill in.
    Future<void>.microtask(_initialize);
    ref.onDispose(() => _scrubTimer?.cancel());
    // We need a placeholder meta for the loading shell. For disk sources we
    // don't have it yet; use a sentinel and replace once loaded. The page
    // guards on isLoading.
    if (source is InMemoryPreviewSource) {
      final s = source as InMemoryPreviewSource;
      return PreviewState(
        meta: s.meta,
        totalSampleCount: s.samples.length,
        isLoading: true,
      );
    }
    final d = source as DiskPreviewSource;
    // Placeholder meta until the async load completes. The page shows a
    // loading indicator while [isLoading] is true.
    return PreviewState(
      meta: SessionMeta(
        sessionId: d.sessionId,
        topic: d.topic,
        trialNumber: d.trialNumber,
        sampleRateHz: 0,
        startTime: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        durationMs: 0,
        sampleCount: 0,
        markerCount: 0,
      ),
      totalSampleCount: 0,
      isLoading: true,
    );
  }

  StorageRepository get _storage => ref.read(storageRepositoryProvider);

  Future<void> _initialize() async {
    try {
      final SessionMeta meta;
      final int total;
      final List<BufferedSample> firstChunk;

      if (source is InMemoryPreviewSource) {
        final s = source as InMemoryPreviewSource;
        meta = s.meta;
        total = s.samples.length;
        firstChunk = _sliceInMemory(s.samples, 0, _kChunkSize);
      } else {
        final d = source as DiskPreviewSource;
        final loaded = await _storage.readSessionMeta(
          d.topic,
          d.trialNumber,
          d.sessionId,
        );
        if (loaded == null) {
          if (!ref.mounted) return;
          state = state.copyWith(isLoading: false, error: 'Session not found');
          return;
        }
        meta = loaded;
        total = meta.sampleCount;
        firstChunk = await _storage.readSampleChunk(
          d.topic,
          d.trialNumber,
          d.sessionId,
          offset: 0,
          count: _kChunkSize,
        );
      }

      if (!ref.mounted) return;
      final stats = SessionStatsCalculator.compute(firstChunk, meta);
      state = PreviewState(
        meta: meta,
        totalSampleCount: total,
        stats: stats,
        currentChunk: firstChunk,
        scrubPositionMs: 0,
        selectedWheel: PreviewWheelSelection.both,
        isLoading: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  /// Sets the scrub position (ms from session start) and schedules a debounced
  /// chunk load around that position.
  void setScrub(int ms) {
    final clamped = ms.clamp(0, meta.durationMs);
    state = state.copyWith(scrubPositionMs: clamped);
    _scrubTimer?.cancel();
    _scrubTimer = Timer(
      const Duration(milliseconds: _kScrubDebounceMs),
      _loadChunkAtScrub,
    );
  }

  /// Sets the selected wheel for chart display. Does not reload — just filters
  /// the displayed chunk client-side.
  void setWheel(PreviewWheelSelection selection) {
    state = state.copyWith(selectedWheel: selection);
  }

  /// Reloads the chunk centered on the current scrub position.
  Future<void> _loadChunkAtScrub() async {
    if (!ref.mounted) return;
    final center = _scrubToSampleIndex(state.scrubPositionMs);
    final offset = (center - _kHalfWindow).clamp(0, _maxOffset());
    try {
      final chunk = await _loadChunk(offset, _kChunkSize);
      if (!ref.mounted) return;
      state = state.copyWith(currentChunk: chunk);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(error: '$e');
    }
  }

  /// Maps a scrub position (ms from start) to a sample index.
  int _scrubToSampleIndex(int ms) {
    final rate = state.meta.sampleRateHz;
    if (rate <= 0) return 0;
    return ((ms / 1000.0) * rate).round();
  }

  int _maxOffset() {
    final total = state.totalSampleCount;
    return (total - _kChunkSize).clamp(0, total);
  }

  Future<List<BufferedSample>> _loadChunk(int offset, int count) async {
    if (source is InMemoryPreviewSource) {
      final s = source as InMemoryPreviewSource;
      return _sliceInMemory(s.samples, offset, count);
    }
    final d = source as DiskPreviewSource;
    return _storage.readSampleChunk(
      d.topic,
      d.trialNumber,
      d.sessionId,
      offset: offset,
      count: count,
    );
  }

  List<BufferedSample> _sliceInMemory(
    List<BufferedSample> samples,
    int offset,
    int count,
  ) {
    if (offset < 0) {
      throw ArgumentError('offset must be >= 0: $offset');
    }
    if (offset >= samples.length) return const [];
    final end = (offset + count).clamp(0, samples.length);
    return samples.sublist(offset, end);
  }

  /// Convenience accessor for the page.
  SessionMeta get meta => state.meta;
}

final previewControllerProvider =
    NotifierProvider.family<PreviewController, PreviewState, PreviewSource>(
      PreviewController.new,
    );

/// Filters a chunk of [BufferedSample]s to a single [WheelSide]. Returns the
/// input unchanged when [selection] is [PreviewWheelSelection.both].
///
/// Pure logic — exported for unit testing.
List<BufferedSample> filterByWheel(
  List<BufferedSample> samples,
  PreviewWheelSelection selection,
) {
  return switch (selection) {
    PreviewWheelSelection.both => samples,
    PreviewWheelSelection.left =>
      samples.where((s) => s.wheel == WheelSide.left).toList(growable: false),
    PreviewWheelSelection.right =>
      samples.where((s) => s.wheel == WheelSide.right).toList(growable: false),
  };
}

/// Extracts the [ImuReading] list from a chunk of [BufferedSample]s for chart
/// rendering.
List<ImuReading> toReadings(List<BufferedSample> samples) {
  return samples.map((s) => s.reading).toList(growable: false);
}
