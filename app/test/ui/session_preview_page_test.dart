import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/preview_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/session_preview_page.dart';

import '../helpers/pump.dart';

BufferedSample _sample(
  ImuReading reading, {
  WheelSide wheel = WheelSide.left,
}) {
  return BufferedSample(
    reading: reading,
    wheel: wheel,
    timestampAppMs: 0,
    timestampSyncedMs: 0,
  );
}

SessionMeta _meta({int durationMs = 10000, int sampleCount = 100}) {
  return SessionMeta(
    sessionId: 'deadbeef',
    topic: 'test-topic',
    trialNumber: 1,
    sampleRateHz: 100,
    startTime: DateTime.utc(2024, 1, 1),
    durationMs: durationMs,
    sampleCount: sampleCount,
    markerCount: 2,
    driftResidualRmsMsLeft: 1.0,
    driftResidualRmsMsRight: 3.5,
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
  setUpAll(disableGoogleFontsFetching);

  /// Mixed-wheel samples so both L and R charts render in "Both" mode.
  List<BufferedSample> _mixedSamples(int count) => List.generate(
        count,
        (i) => _sample(
          _r(i),
          wheel: i % 2 == 0 ? WheelSide.left : WheelSide.right,
        ),
      );

  /// Pumps the page in a tall viewport so both chart sections are visible.
  Future<void> _pumpPage(
    WidgetTester tester,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: child,
      ),
    );
  }

  testWidgets('renders loading state then summary + charts for in-memory source',
      (tester) async {
    final samples = _mixedSamples(100);
    final meta = _meta();
    final source = InMemoryPreviewSource(meta: meta, samples: samples);

    await _pumpPage(
      tester,
      ProviderScope(
        child: SessionPreviewPage(source: source),
      ),
    );
    // Initial loading frame.
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // Let the microtask + async init complete.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // AppBar shows session id.
    expect(find.text('deadbeef'), findsOneWidget);
    // Summary card.
    expect(find.text('Summary'), findsOneWidget);
    expect(find.textContaining('samples'), findsOneWidget);
    expect(find.textContaining('marks'), findsOneWidget);
    // Sync quality badge — "Fair" because right drift = 3.5 ms.
    expect(find.textContaining('sync Fair'), findsOneWidget);
    // Stat tiles.
    expect(find.text('Mean accel'), findsOneWidget);
    expect(find.text('Peak accel'), findsOneWidget);
    expect(find.text('Mean gyro'), findsOneWidget);
    expect(find.text('Peak gyro'), findsOneWidget);
    // Scrub slider.
    expect(find.byType(Slider), findsOneWidget);
    // Wheel selector chips.
    expect(find.text('Both'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    // Chart titles.
    expect(find.text('Accelerometer (g)'), findsOneWidget);
    expect(find.text('Gyroscope (dps)'), findsOneWidget);
    // Both wheels -> two 'L' and two 'R' labels (accel + gyro).
    expect(find.text('L'), findsNWidgets(2));
    expect(find.text('R'), findsNWidgets(2));
  });

  testWidgets('selecting Left wheel shows a single chart with L label',
      (tester) async {
    final samples = _mixedSamples(100);
    final meta = _meta();
    final source = InMemoryPreviewSource(meta: meta, samples: samples);

    await _pumpPage(
      tester,
      ProviderScope(
        child: SessionPreviewPage(source: source),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Left'));
    await tester.pumpAndSettle();

    // Only one 'L' label per chart section (accel + gyro) = 2 total.
    expect(find.text('L'), findsNWidgets(2));
    expect(find.text('R'), findsNothing);
  });

  testWidgets('scrub slider updates scrub position label', (tester) async {
    final samples = _mixedSamples(100);
    final meta = _meta(durationMs: 10000, sampleCount: 100);
    final source = InMemoryPreviewSource(meta: meta, samples: samples);

    await _pumpPage(
      tester,
      ProviderScope(
        child: SessionPreviewPage(source: source),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Initial scrub label = 0.0s
    expect(find.text('0.0s'), findsOneWidget);

    // Drag the slider to ~50%.
    final sliderFinder = find.byType(Slider);
    await tester.drag(sliderFinder, const Offset(200, 0));
    await tester.pump();

    // Scrub label should have changed (no longer 0.0s).
    expect(find.text('0.0s'), findsNothing);
  });

  testWidgets('shows error view when disk source session is missing',
      (tester) async {
    final storage = InMemoryStorageRepository();
    final source = DiskPreviewSource(
      topic: 'nope',
      trialNumber: 1,
      sessionId: 'missing',
    );

    await _pumpPage(
      tester,
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWith((ref) => storage),
        ],
        child: SessionPreviewPage(source: source),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('Could not load session'), findsOneWidget);
  });

  testWidgets('renders disk-backed session after async load', (tester) async {
    final storage = InMemoryStorageRepository();
    final samples = _mixedSamples(50);
    final meta = _meta(sampleCount: 50);
    await storage.saveSession('test-topic', meta, samples);
    final source = DiskPreviewSource(
      topic: 'test-topic',
      trialNumber: 1,
      sessionId: 'deadbeef',
    );

    await _pumpPage(
      tester,
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWith((ref) => storage),
        ],
        child: SessionPreviewPage(source: source),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('deadbeef'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Accelerometer (g)'), findsOneWidget);
  });
}
