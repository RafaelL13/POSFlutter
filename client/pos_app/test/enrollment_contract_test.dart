import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/schema_v3.dart';
void main(){test('migración mantiene PointOfSale por defecto para dispositivos existentes',(){final sql=schemaV3Statements.join('\n');expect(sql,contains("DEFAULT 'PointOfSale'"));expect(sql,contains("'AdminReadOnly'"));});}
