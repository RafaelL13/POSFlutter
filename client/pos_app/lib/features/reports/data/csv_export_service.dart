import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pos_app/database/app_database.dart';
final class CsvExportService {CsvExportService(this._db);final AppDatabase _db;Future<File> sales() async {final db=await _db.open();final rows=await db.query('sales',orderBy:'sale_datetime DESC');final dir=await getApplicationDocumentsDirectory();final f=File('${dir.path}/sales.csv');final b=StringBuffer('folio,date,total_cents,status\n');for(final r in rows){b.writeln('${r['folio']},${r['sale_datetime']},${r['total_cents']},${r['status']}');}return f.writeAsString(b.toString(),flush:true);}}
