import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';

final class RemoteReportXlsxService {
  Future<File> export(RemoteReportTable table) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Reporte'];
    if (workbook.tables.containsKey('Sheet1')) {
      workbook.delete('Sheet1');
    }

    sheet.appendRow(
      table.columns.map((column) => TextCellValue(_title(column))).toList(),
    );

    for (final row in table.rows) {
      sheet.appendRow(
        table.columns.map((column) => _cell(row[column])).toList(),
      );
    }

    if (table.note != null && table.note!.trim().isNotEmpty) {
      sheet.appendRow(const []);
      sheet.appendRow([TextCellValue(table.note!)]);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('No fue posible generar el archivo XLSX.');
    }

    final directory = await getApplicationDocumentsDirectory();
    final safeName = table.title.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    final file = File('${directory.path}/reporte_pos_$safeName.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  CellValue _cell(Object? value) {
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value?.toString() ?? '');
  }

  String _title(String value) {
    final spaced = value
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .trim();
    return spaced.isEmpty
        ? value
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
