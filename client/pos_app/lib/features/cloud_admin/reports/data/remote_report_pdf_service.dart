import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';

final class RemoteReportPdfService {
  Future<File> export(RemoteReportTable table) async {
    final document = pw.Document(
      title: 'POSFlutter · ${table.title}',
      author: 'POSFlutter Admin',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'POSFlutter Admin',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(table.title, style: const pw.TextStyle(fontSize: 13)),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: table.columns.map(_title).toList(),
            data: table.rows
                .map(
                  (row) => table.columns
                      .map((column) => _format(column, row[column]))
                      .toList(),
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
          ),
          if (table.note != null && table.note!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(table.note!, style: const pw.TextStyle(fontSize: 8)),
          ],
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7),
          ),
        ),
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final safeName = table.title.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    final file = File('${directory.path}/reporte_pos_$safeName.pdf');
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  String _format(String column, Object? value) {
    if (column.endsWith('Cents') && value is num) {
      final cents = value.toInt();
      final sign = cents < 0 ? '-' : '';
      final absolute = cents.abs();
      final pesos = absolute ~/ 100;
      final decimals = (absolute % 100).toString().padLeft(2, '0');
      return '$sign$$pesos.$decimals';
    }
    if (column.toLowerCase().contains('percent') && value is num) {
      return '${value.toStringAsFixed(2)}%';
    }
    return value?.toString() ?? '';
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
