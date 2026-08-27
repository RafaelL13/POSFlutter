import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';

final class RemoteReportCsvService {
  Future<File> export(RemoteReportTable table) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeName = table.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final file = File('${directory.path}/reporte_remoto_$safeName.csv');
    return file.writeAsString(buildCsv(table), flush: true);
  }

  String buildCsv(RemoteReportTable table) {
    final buffer = StringBuffer()..writeln(table.columns.map(_escape).join(','));
    for (final row in table.rows) {
      buffer.writeln(table.columns.map((column) => _escape(row[column])).join(','));
    }
    return buffer.toString();
  }

  String _escape(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }
}
