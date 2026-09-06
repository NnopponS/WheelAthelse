import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/protocol_template.dart';

void main() {
  group('ProtocolTemplate — serialization', () {
    test('toJson/fromJson round-trip preserves all fields', () {
      final original = ProtocolTemplate(
        id: '18f5e3a2b1c',
        name: '20m Sprint Test',
        description: 'From standing start, 20m max effort',
        topicName: 'sprint_20m',
        targetTrialCount: 5,
        sampleRateHz: 100,
        createdAt: DateTime.utc(2026, 7, 2, 10, 30, 0),
      );
      final json = original.toJson();
      final restored = ProtocolTemplate.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.topicName, original.topicName);
      expect(restored.targetTrialCount, original.targetTrialCount);
      expect(restored.sampleRateHz, original.sampleRateHz);
      expect(restored.createdAt, original.createdAt);
    });

    test('toJson/fromJson round-trip with null description', () {
      final original = ProtocolTemplate(
        id: 'abc123',
        name: 'Balance Test',
        topicName: 'balance',
        targetTrialCount: 3,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final restored = ProtocolTemplate.fromJson(original.toJson());

      expect(restored.description, isNull);
      expect(restored.sampleRateHz, 100); // default
    });

    test('fromJson defaults sampleRateHz to 100 when missing', () {
      final json = {
        'id': 'abc',
        'name': 'Test',
        'description': null,
        'topic_name': 'topic',
        'target_trial_count': 1,
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        // sample_rate_hz omitted
      };
      final template = ProtocolTemplate.fromJson(json);
      expect(template.sampleRateHz, 100);
    });

    test('copyWith updates only specified fields', () {
      final original = ProtocolTemplate(
        id: 'abc',
        name: 'Old',
        topicName: 'old_topic',
        targetTrialCount: 3,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final updated = original.copyWith(name: 'New', targetTrialCount: 7);

      expect(updated.id, 'abc');
      expect(updated.name, 'New');
      expect(updated.topicName, 'old_topic');
      expect(updated.targetTrialCount, 7);
      expect(updated.createdAt, original.createdAt);
    });
  });
}
