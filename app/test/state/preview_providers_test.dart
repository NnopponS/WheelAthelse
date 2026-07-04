import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/preview_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Builds a [BufferedSample] with a given [ImuReading] and wheel side.
BufferedSample _sample(
  ImuReading reading, {
  WheelSide wheel = WheelSide.left,
  int timestampAppMs = 0,
  double timestampSyncedMs = 0,
}) {
  return BufferedSample(
    reading: reading,
    wheel: wheel,
    timestampAppMs: timestampAppMs,
    timestampSyncedMs: timestampSyncedMs,
  );
}

SessionMeta _meta({
  int durationMs = 10000,
  int sampleCount = 100,
  int sampleRateHz = 100,
  double? driftLeft,
  double? driftRight,
}) {
  return SessionMeta(
    sessionId: 'deadbeef',
    topic: 'test-topic',
    trialNumber: 1,
    sampleRateHz: sampleRateHz,
    startTime: DateTime.utc(2024, 1, 1),
    durationMs: durationMs,
    sampleCount: sampleCount,
    markerCount: 0,
    driftResidualRmsMsLeft: driftLeft,
    driftResidualRmsMsRight: driftRight,
  );
}

ImuReading _r(int seq) => ImuReading(
      seq: seq,
      tDeviceUs: seq * 10000,
      ax: 1.0,
      ay: 0.0,
      az: 0.0,
      gx: 0.0,
      gy: 2.0,
      gz: 0.0,
    );

void main() {
  group('filterByWheel', () {
    final left = _sample(_r(0), wheel: WheelSide.left);
    final right = _sample(_r(1), wheel: WheelSide.right);
    final mixed = [left, right, left, right];

    test('both returns input unchanged', () {
      expect(filterByWheel(mixed, PreviewWheelSelection.both), same(mixed));
    });

    test('left filters to left-only samples', () {
      final out = filterByWheel(mixed, PreviewWheelSelection.left);
      expect(out.length, 2);
      expect(out.every((s) => s.wheel == WheelSide.left), isTrue);
    });

    test('right filters to right-only samples', () {
      final out = filterByWheel(mixed, PreviewWheelSelection.right);
      expect(out.length, 2);
      expect(out.every((s) => s.wheel == WheelSide.right), isTrue);
    });

    test('empty input -> empty output', () {
      expect(filterByWheel(const [], PreviewWheelSelection.left), isEmpty);
    });
  });

  group('toReadings', () {
    test('extracts ImuReading list from BufferedSample list', () {
      final samples = [
        _sample(_r(0)),
        _sample(_r(1)),
        _sample(_r(2)),
      ];
      final readings = toReadings(samples);
      expect(readings.length, 3);
      expect(readings[0].seq, 0);
      expect(readings[1].seq, 1);
      expect(readings[2].seq, 2);
    });

    test('empty input -> empty output', () {
      expect(toReadings(const []), isEmpty);
    });
  });

  group('PreviewController (InMemoryPreviewSource)', () {
    late ProviderContainer container;

    tearDown(() => container.dispose());

    test('build sets loading state then microtask loads meta + first chunk',
        () async {
      final samples = List.generate(100, (i) => _sample(_r(i)));
      final meta = _meta(sampleCount: 100, durationMs: 10000);
      final source = InMemoryPreviewSource(meta: meta, samples: samples);

      container = ProviderContainer();
      final init = container.read(previewControllerProvider(source));
      // Synchronous build: loading shell with meta already known.
      expect(init.isLoading, isTrue);
      expect(init.meta.sessionId, 'deadbeef');
      expect(init.totalSampleCount, 100);

      // Allow the microtask + async init to complete.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(previewControllerProvider(source));
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.totalSampleCount, 100);
      expect(state.currentChunk.length, 100); // all fit in one chunk
      expect(state.stats, isNotNull);
      expect(state.stats!.sampleCount, 100);
      expect(state.scrubPositionMs, 0);
      expect(state.selectedWheel, PreviewWheelSelection.both);
    });

    test('large in-memory session only loads first chunk into currentChunk',
        () async {
      final samples = List.generate(2000, (i) => _sample(_r(i)));
      final meta = _meta(sampleCount: 2000, durationMs: 20000);
      final source = InMemoryPreviewSource(meta: meta, samples: samples);

      container = ProviderContainer();
      container.read(previewControllerProvider(source));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(previewControllerProvider(source));
      expect(state.currentChunk.length, 500); // _kChunkSize
      expect(state.totalSampleCount, 2000);
    });

    test('setWheel updates selectedWheel without reload', () async {
      final samples = List.generate(100, (i) => _sample(_r(i)));
      final meta = _meta(sampleCount: 100);
      final source = InMemoryPreviewSource(meta: meta, samples: samples);

      container = ProviderContainer();
      container.read(previewControllerProvider(source));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      container
          .read(previewControllerProvider(source).notifier)
          .setWheel(PreviewWheelSelection.left);
      final state = container.read(previewControllerProvider(source));
      expect(state.selectedWheel, PreviewWheelSelection.left);
    });

    test('setScrub clamps to [0, durationMs]', () async {
      final samples = List.generate(100, (i) => _sample(_r(i)));
      final meta = _meta(sampleCount: 100, durationMs: 10000);
      final source = InMemoryPreviewSource(meta: meta, samples: samples);

      container = ProviderContainer();
      container.read(previewControllerProvider(source));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(previewControllerProvider(source).notifier);
      notifier.setScrub(-500);
      expect(
        container.read(previewControllerProvider(source)).scrubPositionMs,
        0,
      );
      notifier.setScrub(99999);
      expect(
        container.read(previewControllerProvider(source)).scrubPositionMs,
        10000,
      );
      notifier.setScrub(5000);
      expect(
        container.read(previewControllerProvider(source)).scrubPositionMs,
        5000,
      );
    });

    test('setScrub loads a chunk around the scrub position after debounce',
        () async {
      // 2000 samples, 100 Hz, 20s duration. Scrub to 10s -> center index 1000.
      final samples = List.generate(
        2000,
        (i) => _sample(
          _r(i),
          timestampSyncedMs: i * 10.0,
          wheel: i % 2 == 0 ? WheelSide.left : WheelSide.right,
        ),
      );
      final meta = _meta(sampleCount: 2000, durationMs: 20000);
      final source = InMemoryPreviewSource(meta: meta, samples: samples);

      container = ProviderContainer();
      container.read(previewControllerProvider(source));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Initial chunk is samples [0..500).
      var state = container.read(previewControllerProvider(source));
      expect(state.currentChunk.first.reading.seq, 0);

      // Scrub to 10s -> center 1000 -> offset 750 -> chunk [750..1250).
      container
          .read(previewControllerProvider(source).notifier)
          .setScrub(10000);

      // Before debounce fires, scrub position is updated but chunk unchanged.
      state = container.read(previewControllerProvider(source));
      expect(state.scrubPositionMs, 10000);
      expect(state.currentChunk.first.reading.seq, 0);

      // After debounce (200ms) + microtask, chunk reloads.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      state = container.read(previewControllerProvider(source));
      expect(state.currentChunk.first.reading.seq, 750);
      expect(state.currentChunk.length, 500);
    });
  });

  group('PreviewController (DiskPreviewSource)', () {
    late InMemoryStorageRepository storage;
    late ProviderContainer container;

    setUp(() {
      storage = InMemoryStorageRepository();
    });

    tearDown(() => container.dispose());

    test('loads meta + first chunk from disk on init', () async {
      final samples = List.generate(100, (i) => _sample(_r(i)));
      final meta = _meta(sampleCount: 100, durationMs: 10000);
      await storage.saveSession('test-topic', meta, samples);

      container = ProviderContainer(overrides: [
        storageRepositoryProvider.overrideWith((ref) => storage),
      ]);
      final source = DiskPreviewSource(
        topic: 'test-topic',
        trialNumber: 1,
        sessionId: 'deadbeef',
      );

      final init = container.read(previewControllerProvider(source));
      expect(init.isLoading, isTrue);
      // Placeholder meta for disk source until async load completes.
      expect(init.meta.sampleRateHz, 0);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(previewControllerProvider(source));
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.meta.sessionId, 'deadbeef');
      expect(state.meta.sampleRateHz, 100);
      expect(state.totalSampleCount, 100);
      expect(state.currentChunk.length, 100);
      expect(state.stats, isNotNull);
      expect(state.stats!.sampleCount, 100);
    });

    test('missing session sets error state', () async {
      container = ProviderContainer(overrides: [
        storageRepositoryProvider.overrideWith((ref) => storage),
      ]);
      final source = DiskPreviewSource(
        topic: 'nope',
        trialNumber: 1,
        sessionId: 'missing',
      );

      container.read(previewControllerProvider(source));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(previewControllerProvider(source));
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
      expect(state.currentChunk, isEmpty);
    });

    test('scrub loads chunk from disk around scrub position', () async {
      final samples = List.generate(
        2000,
        (i) => _sample(
          _r(i),
          timestampSyncedMs: i * 10.0,
        ),
      );
      final meta = _meta(sampleCount: 2000, durationMs: 20000);
      await storage.saveSession('test-topic', meta, samples);

      container = ProviderContainer(overrides: [
        storageRepositoryProvider.overrideWith((ref) => storage),
      ]);
      final source = DiskPreviewSource(
        topic: 'test-topic',
        trialNumber: 1,
        sessionId: 'deadbeef',
      );

      container.read(previewControllerProvider(source));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      container
          .read(previewControllerProvider(source).notifier)
          .setScrub(10000);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final state = container.read(previewControllerProvider(source));
      expect(state.currentChunk.first.reading.seq, 750);
      expect(state.currentChunk.length, 500);
    });
  });

  group('PreviewSource equality', () {
    test('DiskPreviewSource value equality', () {
      const a = DiskPreviewSource(topic: 't', trialNumber: 1, sessionId: 's');
      const b = DiskPreviewSource(topic: 't', trialNumber: 1, sessionId: 's');
      const c = DiskPreviewSource(topic: 't', trialNumber: 2, sessionId: 's');
      expect(a == b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
      expect(a == c, isFalse);
    });

    test('InMemoryPreviewSource identity equality on samples list', () {
      final meta = _meta();
      final samples = [_sample(_r(0))];
      final a = InMemoryPreviewSource(meta: meta, samples: samples);
      final b = InMemoryPreviewSource(meta: meta, samples: samples);
      final c = InMemoryPreviewSource(
        meta: meta,
        samples: [_sample(_r(0))],
      );
      expect(a == b, isTrue); // same samples identity
      expect(a == c, isFalse); // different samples identity
    });
  });
}
