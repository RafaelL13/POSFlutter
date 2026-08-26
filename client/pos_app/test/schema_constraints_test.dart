import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
void main(){test('esquema protege cantidades y dinero enteros',(){final sql=schemaV1Statements.join('\n');expect(sql,contains("typeof(quantity)='integer'"));expect(sql,contains("typeof(sale_price_cents)='integer'"));expect(sql,contains('sale_detail_lots'));});test('v2 crea conflictos y cursor; v3 DeviceMode',(){expect(schemaV2Statements.join('\n'),contains('sync_conflicts'));expect(schemaV2Statements.join('\n'),contains('sync_pull_cursor'));expect(schemaV3Statements.join('\n'),contains('AdminReadOnly'));});}
