import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/database/schema_v3.dart';

void main() {
  test(
    'migración mantiene PointOfSale por defecto para dispositivos existentes',
    () {
      final sql = schemaV3Statements.join('\n');
      expect(sql, contains("DEFAULT 'PointOfSale'"));
      expect(sql, contains("'AdminReadOnly'"));
    },
  );

  test('device enrollment wire values remain stable', () {
    expect(DeviceMode.pointOfSale.wireValue, 'PointOfSale');
    expect(DeviceMode.adminReadOnly.wireValue, 'AdminReadOnly');
    expect(DeviceMode.tryParse('PointOfSale'), DeviceMode.pointOfSale);
    expect(DeviceMode.tryParse('AdminReadOnly'), DeviceMode.adminReadOnly);
    expect(DeviceMode.tryParse('invalid'), isNull);
  });
}
