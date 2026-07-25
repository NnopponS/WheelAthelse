import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/quality_badge.dart';
import 'package:wheelathlete/records/session_model.dart';

void main() {
  group('QualityBadge.fromDriftRms', () {
    test('0 -> good', () {
      expect(QualityBadge.fromDriftRms(0), SyncQuality.good);
    });

    test('1.9 -> good', () {
      expect(QualityBadge.fromDriftRms(1.9), SyncQuality.good);
    });

    test('2.0 -> fair', () {
      expect(QualityBadge.fromDriftRms(2.0), SyncQuality.fair);
    });

    test('3.0 -> fair', () {
      expect(QualityBadge.fromDriftRms(3.0), SyncQuality.fair);
    });

    test('5.0 -> fair (inclusive upper bound)', () {
      expect(QualityBadge.fromDriftRms(5.0), SyncQuality.fair);
    });

    test('5.1 -> poor', () {
      expect(QualityBadge.fromDriftRms(5.1), SyncQuality.poor);
    });

    test('100 -> poor', () {
      expect(QualityBadge.fromDriftRms(100), SyncQuality.poor);
    });

    test('null -> unknown', () {
      expect(QualityBadge.fromDriftRms(null), SyncQuality.unknown);
    });

    test('negative -> good (better than good)', () {
      expect(QualityBadge.fromDriftRms(-1), SyncQuality.good);
    });
  });

  group('QualityBadge.fromMeta', () {
    SessionMeta meta({double? left, double? right}) => SessionMeta(
      sessionId: 'test',
      topic: 'topic',
      trialNumber: 1,
      sampleRateHz: 100,
      startTime: DateTime(2026, 1, 1),
      durationMs: 1000,
      sampleCount: 100,
      markerCount: 0,
      driftResidualRmsMsLeft: left,
      driftResidualRmsMsRight: right,
    );

    test('both wheels good -> good', () {
      expect(
        QualityBadge.fromMeta(meta(left: 1.0, right: 1.5)),
        SyncQuality.good,
      );
    });

    test('one good one poor -> poor (uses max)', () {
      expect(
        QualityBadge.fromMeta(meta(left: 1.0, right: 6.0)),
        SyncQuality.poor,
      );
    });

    test('one fair one good -> fair (uses max)', () {
      expect(
        QualityBadge.fromMeta(meta(left: 1.0, right: 3.0)),
        SyncQuality.fair,
      );
    });

    test('left null, right set -> based on right', () {
      expect(
        QualityBadge.fromMeta(meta(left: null, right: 1.0)),
        SyncQuality.good,
      );
    });

    test('right null, left set -> based on left', () {
      expect(
        QualityBadge.fromMeta(meta(left: 6.0, right: null)),
        SyncQuality.poor,
      );
    });

    test('both null -> unknown', () {
      expect(
        QualityBadge.fromMeta(meta(left: null, right: null)),
        SyncQuality.unknown,
      );
    });
  });

  group('QualityBadge.color', () {
    test('good -> green', () {
      expect(QualityBadge.color(SyncQuality.good), const Color(0xFF4CAF50));
    });

    test('fair -> amber', () {
      expect(QualityBadge.color(SyncQuality.fair), const Color(0xFFFFC107));
    });

    test('poor -> red', () {
      expect(QualityBadge.color(SyncQuality.poor), const Color(0xFFF44336));
    });

    test('unknown -> grey', () {
      expect(QualityBadge.color(SyncQuality.unknown), const Color(0xFF9E9E9E));
    });
  });
}
