import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

void main() {
  group('MarkerEvent', () {
    test('records timestamp + label + relative offset', () {
      const m = MarkerEvent(
        timestampAppMs: 1000,
        label: 'push-off',
        offsetFromStartMs: 500,
      );
      expect(m.timestampAppMs, 1000);
      expect(m.label, 'push-off');
      expect(m.offsetFromStartMs, 500);
    });

    test('default label is empty string', () {
      const m = MarkerEvent(timestampAppMs: 0, offsetFromStartMs: 0);
      expect(m.label, '');
    });
  });

  group('SessionConfig', () {
    test('holds topic, trial number, sample rate, athlete name', () {
      const cfg = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 3,
        sampleRateHz: 100,
        athleteName: 'Athlete A',
        notes: 'calibration run',
      );
      expect(cfg.topic, 'sprint_test');
      expect(cfg.trialNumber, 3);
      expect(cfg.sampleRateHz, 100);
      expect(cfg.athleteName, 'Athlete A');
      expect(cfg.notes, 'calibration run');
    });

    test('trial folder name is zero-padded to 2 digits', () {
      const cfg1 = SessionConfig(
        topic: 'x',
        trialNumber: 1,
        sampleRateHz: 100,
      );
      expect(cfg1.trialFolderName, 'trial_01');

      const cfg10 = SessionConfig(
        topic: 'x',
        trialNumber: 10,
        sampleRateHz: 100,
      );
      expect(cfg10.trialFolderName, 'trial_10');
    });

    test('session id is timestamp-based and unique-ish', () {
      const cfg = SessionConfig(
        topic: 'x',
        trialNumber: 1,
        sampleRateHz: 100,
      );
      final id = cfg.sessionId;
      expect(id, isNotEmpty);
      // Should be a hex timestamp or similar — just check it's a valid string.
      expect(id.length, greaterThan(4));
    });
  });

  group('SessionMeta', () {
    test('serializes to JSON with all fields', () {
      final meta = SessionMeta(
        sessionId: 'abc123',
        topic: 'sprint_test',
        trialNumber: 3,
        athleteName: 'Athlete A',
        sampleRateHz: 100,
        startTime: DateTime.utc(2026, 6, 29, 10, 30, 0),
        durationMs: 60000,
        sampleCount: 6000,
        markerCount: 5,
        offsetUsLeft: 100,
        offsetUsRight: -200,
        driftResidualRmsMsLeft: 0.5,
        driftResidualRmsMsRight: 0.8,
        notes: 'calibration run',
        videoFileName: 'cam01.mp4',
      );
      final json = meta.toJson();

      expect(json['session_id'], 'abc123');
      expect(json['topic'], 'sprint_test');
      expect(json['trial_number'], 3);
      expect(json['athlete_name'], 'Athlete A');
      expect(json['sample_rate_hz'], 100);
      expect(json['start_time'], '2026-06-29T10:30:00.000Z');
      expect(json['duration_ms'], 60000);
      expect(json['sample_count'], 6000);
      expect(json['marker_count'], 5);
      expect(json['offset_us_left'], 100);
      expect(json['offset_us_right'], -200);
      expect(json['drift_residual_rms_ms_left'], 0.5);
      expect(json['drift_residual_rms_ms_right'], 0.8);
      expect(json['notes'], 'calibration run');
      expect(json['video_file_name'], 'cam01.mp4');
    });

    test('deserializes from JSON round-trip', () {
      final original = SessionMeta(
        sessionId: 'xyz',
        topic: 'test',
        trialNumber: 1,
        athleteName: 'Bob',
        sampleRateHz: 200,
        startTime: DateTime.utc(2026, 1, 1),
        durationMs: 1000,
        sampleCount: 200,
        markerCount: 2,
        offsetUsLeft: 10,
        offsetUsRight: -10,
        driftResidualRmsMsLeft: 0.1,
        driftResidualRmsMsRight: 0.2,
        notes: 'test note',
        videoFileName: null,
      );
      final json = original.toJson();
      final restored = SessionMeta.fromJson(json);

      expect(restored.sessionId, original.sessionId);
      expect(restored.topic, original.topic);
      expect(restored.trialNumber, original.trialNumber);
      expect(restored.athleteName, original.athleteName);
      expect(restored.sampleRateHz, original.sampleRateHz);
      expect(restored.startTime, original.startTime);
      expect(restored.durationMs, original.durationMs);
      expect(restored.sampleCount, original.sampleCount);
      expect(restored.markerCount, original.markerCount);
      expect(restored.offsetUsLeft, original.offsetUsLeft);
      expect(restored.offsetUsRight, original.offsetUsRight);
      expect(restored.driftResidualRmsMsLeft, original.driftResidualRmsMsLeft);
      expect(restored.driftResidualRmsMsRight, original.driftResidualRmsMsRight);
      expect(restored.notes, original.notes);
      expect(restored.videoFileName, original.videoFileName);
    });

    test('handles null optional fields in fromJson', () {
      final meta = SessionMeta.fromJson({
        'session_id': 's1',
        'topic': 't',
        'trial_number': 1,
        'athlete_name': null,
        'sample_rate_hz': 100,
        'start_time': '2026-06-29T10:30:00.000Z',
        'duration_ms': 0,
        'sample_count': 0,
        'marker_count': 0,
        'offset_us_left': null,
        'offset_us_right': null,
        'drift_residual_rms_ms_left': null,
        'drift_residual_rms_ms_right': null,
        'notes': null,
        'video_file_name': null,
      });
      expect(meta.athleteName, isNull);
      expect(meta.offsetUsLeft, isNull);
      expect(meta.notes, isNull);
      expect(meta.videoFileName, isNull);
    });

    test('tags default to empty list when not provided in constructor', () {
      final meta = SessionMeta(
        sessionId: 's1',
        topic: 't',
        trialNumber: 1,
        sampleRateHz: 100,
        startTime: DateTime.utc(2026, 1, 1),
        durationMs: 0,
        sampleCount: 0,
        markerCount: 0,
      );
      expect(meta.tags, isEmpty);
    });

    test('protocolTemplateId defaults to null when not provided', () {
      final meta = SessionMeta(
        sessionId: 's1',
        topic: 't',
        trialNumber: 1,
        sampleRateHz: 100,
        startTime: DateTime.utc(2026, 1, 1),
        durationMs: 0,
        sampleCount: 0,
        markerCount: 0,
      );
      expect(meta.protocolTemplateId, isNull);
    });

    test('serializes tags + protocolTemplateId to JSON', () {
      final meta = SessionMeta(
        sessionId: 'abc',
        topic: 't',
        trialNumber: 1,
        sampleRateHz: 100,
        startTime: DateTime.utc(2026, 1, 1),
        durationMs: 0,
        sampleCount: 0,
        markerCount: 0,
        tags: ['good', 'athlete-A'],
        protocolTemplateId: 'tpl-123',
      );
      final json = meta.toJson();
      expect(json['tags'], ['good', 'athlete-A']);
      expect(json['protocol_template_id'], 'tpl-123');
    });

    test('deserializes tags + protocolTemplateId from JSON round-trip', () {
      final original = SessionMeta(
        sessionId: 'abc',
        topic: 't',
        trialNumber: 1,
        sampleRateHz: 100,
        startTime: DateTime.utc(2026, 1, 1),
        durationMs: 0,
        sampleCount: 0,
        markerCount: 0,
        tags: ['good', 'bad-take'],
        protocolTemplateId: 'tpl-1',
      );
      final restored = SessionMeta.fromJson(original.toJson());
      expect(restored.tags, ['good', 'bad-take']);
      expect(restored.protocolTemplateId, 'tpl-1');
    });

    test('old session JSON without tags/protocolTemplateId defaults correctly',
        () {
      final meta = SessionMeta.fromJson({
        'session_id': 's1',
        'topic': 't',
        'trial_number': 1,
        'sample_rate_hz': 100,
        'start_time': '2026-06-29T10:30:00.000Z',
        'duration_ms': 0,
        'sample_count': 0,
        'marker_count': 0,
      });
      expect(meta.tags, isEmpty);
      expect(meta.protocolTemplateId, isNull);
    });
  });

  group('BufferedSample', () {
    test('holds ImuReading + wheel side + timestamps + marker flag', () {
      const reading = ImuReading(
        seq: 42,
        tDeviceUs: 1000000,
        ax: 1.0,
        ay: 0,
        az: 0,
        gx: 0,
        gy: 0,
        gz: 0,
      );
      const buffered = BufferedSample(
        reading: reading,
        wheel: WheelSide.left,
        timestampAppMs: 2000,
        timestampSyncedMs: 1999.5,
        marker: true,
      );
      expect(buffered.reading.seq, 42);
      expect(buffered.wheel, WheelSide.left);
      expect(buffered.timestampAppMs, 2000);
      expect(buffered.timestampSyncedMs, 1999.5);
      expect(buffered.marker, isTrue);
    });

    test('marker defaults to false', () {
      const buffered = BufferedSample(
        reading: ImuReading(
          seq: 0,
          tDeviceUs: 0,
          ax: 0,
          ay: 0,
          az: 0,
          gx: 0,
          gy: 0,
          gz: 0,
        ),
        wheel: WheelSide.right,
        timestampAppMs: 0,
        timestampSyncedMs: 0,
      );
      expect(buffered.marker, isFalse);
    });
  });
}
