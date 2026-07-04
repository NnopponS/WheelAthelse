# Phase 4 Architecture — Session Preview & Quality Indicators

## §1 Sample Chunk Reader + Decimation

### Problem
`readSamples()` โหลดทั้ง session (อาจ 60k+ samples). ใช้ใน preview ได้แต่ memory pressure สูง.

### Solution
เพิ่ม `readSampleChunk()` ใน StorageRepository — อ่านเป็น chunks ตาม offset + limit (หน่วยเป็น sample index). ใช้ CSV parser ที่มีอยู่แล้วแต่ skip บรรทัดที่ไม่ต้องการ.

```dart
abstract class StorageRepository {
  // ... existing methods ...

  /// Reads a chunk of samples [offset, offset+count) from the session CSV.
  /// Used by the preview page for lazy loading. Returns empty list if
  /// offset is beyond the sample count.
  Future<List<BufferedSample>> readSampleChunk(
    String topic,
    int trialNumber,
    String sessionId, {
    required int offset,
    required int count,
  });
}
```

**PathProviderStorageRepository:** เปิด CSV ทีละบรรทัด, skip `offset` บรรทัด, อ่าน `count` บรรทัด. ใช้ `csv` package stream parser.

**InMemoryStorageRepository:** sublist จาก stored samples list.

### Decimation for chart
Reuse `ImuChartBuffer.decimate()` ที่มีอยู่แล้ว — รับ `targetPoints` และเลือก evenly-spaced samples. สำหรับ preview:
- Window แรก (0-5s): โหลด chunk แรก ~500 samples → decimate เหลือ 80 points
- ตอน scrub: โหลด chunk รอบตำแหน่งที่ scrub ไป → decimate
- Total points ใน chart ไม่เกิน ~500 ทุกกรณี

## §2 Session Stats Computation

### Pure logic class
```dart
class SessionStats {
  final int sampleCount;
  final int durationMs;
  final int dropCount;
  final double? syncQualityMs; // max of left/right driftResidualRmsMs
  final double meanAccelMagnitude;
  final double peakAccelMagnitude;
  final double meanGyroMagnitude;
  final double peakGyroMagnitude;
}

class SessionStatsCalculator {
  /// Computes stats from a chunk of samples (or full session if small).
  static SessionStats compute(List<BufferedSample> samples, SessionMeta meta);
}
```

- accel magnitude = sqrt(ax² + ay² + az²)
- gyro magnitude = sqrt(gx² + gy² + gz²)
- mean + peak คำนวณจาก samples ที่โหลดมา
- dropCount มาจาก SessionMeta (ถ้ามี) หรือคำนวณจาก seq gaps
- syncQuality มาจาก SessionMeta.driftResidualRmsMs (max ของ left/right)

## §3 Quality Badge Color Thresholds

```dart
enum SyncQuality { good, fair, poor, unknown }

class QualityBadge {
  /// Returns the quality level based on drift residual RMS (ms).
  /// Thresholds:
  ///   good  = < 2 ms   (green)
  ///   fair  = 2-5 ms   (amber)
  ///   poor  = > 5 ms   (red)
  ///   unknown = null   (grey)
  static SyncQuality fromDriftRms(double? driftRmsMs);
}
```

Pure logic — ทดสอบได้โดยไม่ต้อง Flutter widget.

## §4 Session Preview Page

### UI Structure
```
SessionPreviewPage (ConsumerStatefulWidget)
├── AppBar: session ID + topic/trial + Export button
├── Summary stats card (duration, samples, drops, sync quality, mean/peak)
├── Scrub slider (Slider widget, 0 to durationMs)
├── Wheel selector (Left / Right / Both toggle)
├── Accel chart (ImuChart, window around scrub position)
├── Gyro chart (ImuChart, window around scrub position)
└── Export/Share FAB
```

### State
```dart
class _SessionPreviewPageState extends ConsumerState<...> {
  double _scrubPosition = 0; // ms from start
  WheelSide _selectedWheel = WheelSide.both; // or left/right
  List<BufferedSample> _currentChunk = [];
  SessionStats? _stats;
  bool _isLoading = false;
}
```

### Lazy load flow
1. initState: load stats (from meta + first chunk for mean/peak)
2. initState: load first chunk (0-500 samples) → display chart
3. User scrubs → debounce 200ms → load chunk around scrub position
4. Chart displays decimated chunk (80 points per axis)

### Chart rendering
- Reuse `ImuChart` widget ที่มีอยู่ (รับ `List<ImuReading>`)
- แปลง `BufferedSample` → `ImuReading` (extract `.reading`)
- Window size: 5s รอบ scrub position (2.5s ก่อน + 2.5s หลัง)
- ถ้า session สั้นกว่า 5s → แสดงทั้งหมด

## §5 Preview Entry Points

### Browse: tap session
- ใน `_SessionListView` ของ BrowsePage: tap session row → push `SessionPreviewPage`
- ไม่ใช่ tap แล้วเปิด dialog — tap ตัว card (ไม่ใช่ปุ่ม share/delete)
- เพิ่ม `onTap` callback ใน `SessionListItem` ที่ navigate ไป preview

### Stopped view: Preview button
- ใน `_buildStoppedView` ของ RecordPage: เพิ่มปุ่ม "Preview" ระหว่าง Re-record และ New Recording
- Preview ใน stopped view ใช้ข้อมูลใน memory (ไม่ต้องอ่านจาก disk — samples ย还在 RecordingNotifier)
- แต่ถ้า user ออกจาก stopped view แล้วกลับมาดูใน Browse → อ่านจาก disk

## §6 Export/Share from Preview

- ปุ่ม Export ใน AppBar ของ SessionPreviewPage
- ใช้ `exportActionsProvider` ที่มีอยู่แล้ว (CSV export + share_plus)
- เหมือนกับ export ใน Browse แต่ทำจากหน้า preview ได้เลย

## §7 Quality Badges in Browse

### SessionListItem changes
- เพิ่ม `syncQuality: SyncQuality?` parameter
- แสดงเป็น small colored dot หรือ StatusBadge ข้าง session ID
- สี: green (good), amber (fair), red (poor), grey (unknown)

### BrowsePage changes
- ใน `_SessionListView`: คำนวณ `QualityBadge.fromDriftRms()` จาก SessionMeta
- ส่ง `syncQuality` ไปยัง `SessionListItem`

## File Impact Summary

### New files
- `app/lib/records/session_stats.dart` — SessionStats + SessionStatsCalculator
- `app/lib/records/quality_badge.dart` — SyncQuality enum + QualityBadge
- `app/lib/ui/session_preview_page.dart` — full preview page
- `app/lib/state/preview_providers.dart` — Riverpod providers for preview

### Modified files
- `app/lib/records/storage_repository.dart` — add readSampleChunk()
- `app/lib/widgets/session_list_item.dart` — add onTap + syncQuality
- `app/lib/ui/browse_page.dart` — wire tap → preview, compute quality badge
- `app/lib/ui/record_page.dart` — add Preview button in stopped view
- `app/lib/widgets/imu_chart.dart` — may need to accept BufferedSample or add adapter

### Test files
- `app/test/records/session_stats_test.dart`
- `app/test/records/quality_badge_test.dart`
- `app/test/records/storage_repository_test.dart` (add chunk tests)
- `app/test/ui/session_preview_page_test.dart`
- `app/test/ui/browse_page_test.dart` (add tap → preview test)
- `app/test/ui/record_page_test.dart` (add preview button test)
- `app/test/widgets/session_list_item_test.dart` (add quality badge test)
