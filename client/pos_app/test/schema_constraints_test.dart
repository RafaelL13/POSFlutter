import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:pos_app/database/schema_v4.dart';
import 'package:pos_app/database/schema_v5.dart';

void main() {
  test('esquema protege cantidades y dinero enteros', () {
    final sql = schemaV1Statements.join('\n');
    expect(sql, contains("typeof(quantity)='integer'"));
    expect(sql, contains("typeof(sale_price_cents)='integer'"));
    expect(sql, contains('sale_detail_lots'));
  });

  test('v2 crea conflictos, v3 DeviceMode y v4 grants de un uso', () {
    expect(schemaV2Statements.join('\n'), contains('sync_conflicts'));
    expect(schemaV2Statements.join('\n'), contains('sync_pull_cursor'));
    expect(schemaV3Statements.join('\n'), contains('AdminReadOnly'));
    final v4 = schemaV4Statements.join('\n');
    expect(v4, contains('special_authorization_grants'));
    expect(v4, contains('consumed_at'));
    expect(v4, contains('performed_by_user_global_id'));
    expect(v4, contains('authorized_by_user_global_id'));
    expect(v4, contains('ix_special_authorization_unconsumed'));
  });

  test('v5 clasifica rechazos sin ampliar los estados de cola', () {
    final v5 = schemaV5Statements.join('\n');
    expect(v5, contains('error_category'));
    expect(v5, contains('error_code'));
    expect(v5, contains('requires_action'));
    expect(v5, isNot(contains('ALTER TABLE sync_queue ADD COLUMN status')));
  });
}
