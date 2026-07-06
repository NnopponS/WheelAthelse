import 'package:excel/excel.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Exporter that creates an Excel (.xlsx) file with L and R worksheets.
class ExcelExporter {
  const ExcelExporter._();

  /// Converts [samples] into a multi-sheet Excel workbook byte list.
  /// L and R samples are put in worksheets 'L' and 'R' respectively,
  /// sorted by `timestampSyncedMs`.
  static List<int> toXlsxBytes(List<BufferedSample> samples) {
    final excel = Excel.createExcel();

    final left = samples.where((s) => s.wheel == WheelSide.left).toList()
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final right = samples.where((s) => s.wheel == WheelSide.right).toList()
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));

    _writeSheet(excel, 'L', left);
    _writeSheet(excel, 'R', right);

    // Delete default Sheet1 if present to keep it clean.
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    return excel.save() ?? const [];
  }

  static void _writeSheet(
    Excel excel,
    String sheetName,
    List<BufferedSample> samples,
  ) {
    // Calling excel[sheetName] automatically creates the sheet if not found.
    final sheet = excel[sheetName];

    final headers = [
      TextCellValue('seq'),
      TextCellValue('wheel'),
      TextCellValue('timestamp_app_ms'),
      TextCellValue('timestamp_utc_ms'),
      TextCellValue('ax'),
      TextCellValue('ay'),
      TextCellValue('az'),
      TextCellValue('gx'),
      TextCellValue('gy'),
      TextCellValue('gz'),
      TextCellValue('marker'),
    ];
    sheet.appendRow(headers);

    for (final s in samples) {
      final wheel = s.wheel == WheelSide.left ? 'L' : 'R';
      final marker = s.marker ? 1 : 0;
      sheet.appendRow([
        IntCellValue(s.reading.seq),
        TextCellValue(wheel),
        IntCellValue(s.timestampAppMs),
        DoubleCellValue(s.timestampSyncedMs),
        DoubleCellValue(s.reading.ax),
        DoubleCellValue(s.reading.ay),
        DoubleCellValue(s.reading.az),
        DoubleCellValue(s.reading.gx),
        DoubleCellValue(s.reading.gy),
        DoubleCellValue(s.reading.gz),
        IntCellValue(marker),
      ]);
    }
  }
}
