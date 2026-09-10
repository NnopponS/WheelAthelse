import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/analysis_review.dart';
import 'package:wheelathlete/widgets/trajectory_chart.dart';

KinematicAnalysis fixture([bool xyOnly = false]) {
  final t = List.generate(100, (i) => 4.02 + i * 0.05);
  final xy = List.generate(100, (i) => [i * 0.02, i * 0.01]);
  return buildKinematicAnalysis(
    times: t,
    xy: xy,
    flags: List.generate(100, (_) => <String>[]),
    signedSpeed: xyOnly ? null : List.filled(100, 0.4),
    yaw: xyOnly ? null : List.generate(100, (i) => i * 0.02),
    yawRate: xyOnly ? null : List.filled(100, 0.4),
    metadata: {
      'session_id': 'synthetic_widget',
      'xy_frame': 'fixture_initial_frame',
    },
  );
}

Future<void> pumpReview(
  WidgetTester tester,
  KinematicAnalysis a, {
  double width = 390,
  double textScale = 1,
  Future<String?> Function()? picker,
  Key? capture,
  String? captureFont,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: captureFont,
        extensions: const [WheelAthleteColors.light],
      ),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AnalysisReview(
                analysis: a,
                points: a.samples
                    .map((p) => TrajectoryPoint(p.xM, p.yM))
                    .toList(),
                pickExportDirectory: picker,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cursor and range map to exact source points without reinference',
    (tester) async {
      final a = fixture();
      await pumpReview(tester, a);
      final slider = tester.widget<Slider>(
        find.byKey(const Key('analysisTimeSlider')),
      );
      slider.onChanged!(37);
      await tester.pump();
      expect(find.textContaining('Time 5.870 s'), findsOneWidget);
      final chart = tester.widget<TrajectoryChart>(
        find.byType(TrajectoryChart),
      );
      expect(chart.selectedIndex, 37);
      expect(chart.points[37].x, a.samples[37].xM);
      final range = tester.widget<RangeSlider>(
        find.byKey(const Key('analysisWindowSlider')),
      );
      range.onChanged!(const RangeValues(20, 40));
      await tester.pump();
      expect(find.textContaining('21 samples | 1.000 s'), findsOneWidget);
      expect(
        tester
            .widget<TrajectoryChart>(find.byType(TrajectoryChart))
            .windowStart,
        20,
      );
      expect(a.samples[20].xM, 0.4); // Original full-session origin retained.
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'XY-only review leaves yaw and longitudinal acceleration unavailable',
    (tester) async {
      await pumpReview(tester, fixture(true));
      tester
          .widget<Slider>(find.byKey(const Key('analysisTimeSlider')))
          .onChanged!(20);
      await tester.pump();
      expect(find.textContaining('Chair yaw: Unavailable'), findsOneWidget);
      expect(
        find.textContaining('Longitudinal acceleration: Unavailable'),
        findsOneWidget,
      );
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const Key('analysisChannel')),
          )
          .onChanged!('yaw_rad');
      await tester.pump();
      expect(
        find.text('Unavailable for this model or data support'),
        findsOneWidget,
      );
    },
  );
  testWidgets('small phone and large text have no layout overflow', (
    tester,
  ) async {
    await pumpReview(tester, fixture(true), width: 320, textScale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'export cancellation has no file operation and re-enables action',
    (tester) async {
      var calls = 0;
      await pumpReview(
        tester,
        fixture(true),
        picker: () async {
          calls++;
          return null;
        },
      );
      final button = find.byKey(const Key('exportAnalysisButton'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(find.textContaining('Saved timeline.csv'), findsNothing);
    },
  );
  testWidgets('export full timeline agrees with chosen window and selection', (
    tester,
  ) async {
    final parent = Directory.systemTemp.createTempSync(
      'analysis_widget_export_',
    );
    addTearDown(() => parent.deleteSync(recursive: true));
    await pumpReview(tester, fixture(), picker: () async => parent.path);
    tester
        .widget<RangeSlider>(find.byKey(const Key('analysisWindowSlider')))
        .onChanged!(const RangeValues(20, 40));
    await tester.pump();
    final button = find.byKey(const Key('exportAnalysisButton'));
    await tester.ensureVisible(button);
    // Await the actual async button action, not the early creation of COMPLETE.
    // The final flush/close and UI state update must both finish before assertions.
    await tester.runAsync(() async {
      final action = tester.widget<FilledButton>(button).onPressed;
      expect(action, isA<Future<void> Function()>());
      await (action as Future<void> Function())();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    final dir = parent.listSync().whereType<Directory>().single;
    final meta =
        jsonDecode(File('${dir.path}/metadata.json').readAsStringSync()) as Map;
    expect(meta['row_count'], 100);
    expect((meta['selected_window'] as Map)['samples'], 21);
    expect(find.textContaining('Saved timeline.csv'), findsOneWidget);
  });
  testWidgets(
    'render source mobile review evidence without a device installation',
    (tester) async {
      const key = Key('analysisEvidenceBoundary');
      String? captureFont;
      // Widget tests normally use Ahem rectangles, unsuitable for human review.
      // An explicitly requested capture may load an existing local system font.
      // Font bytes are neither added to the repository nor distributed.
      final fontPath = Platform.environment['WHEELATHLETE_SCREENSHOT_FONT'];
      if (fontPath != null) {
        captureFont = 'WheelAthleteSourceEvidence';
        await tester.runAsync(() async {
          final bytes = await File(fontPath).readAsBytes();
          final loader = FontLoader('WheelAthleteSourceEvidence')
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        });
      }
      await pumpReview(tester, fixture(true), capture: key, captureFont: captureFont);
      tester
          .widget<Slider>(find.byKey(const Key('analysisTimeSlider')))
          .onChanged!(30);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        expect(bytes!.lengthInBytes, greaterThan(1000));
        final requested = Platform.environment['WHEELATHLETE_SCREENSHOT_DIR'];
        if (requested != null) {
          final out = Directory(requested);
          expect(out.existsSync(), isTrue);
          final name =
              'mobile_source_review_${DateTime.now().microsecondsSinceEpoch}.png';
          File(
            '${out.path}/$name',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
