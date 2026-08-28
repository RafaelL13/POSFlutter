import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/sales/data/sales_read_repository.dart';

final class CsvExportService {
  CsvExportService(this._db);
  final AppDatabase _db;

  Future<File> sales() async {
    final rows = await SalesReadRepository(_db).list();
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/sales.csv');
    final buffer = StringBuffer('folio,date,total_cents,status\n');
    for (final row in rows) {
      buffer.writeln(
        '${row['folio']},${row['sale_datetime']},${row['total_cents']},${row['status']}',
      );
    }
    return file.writeAsString(buffer.toString(), flush: true);
  }
}
