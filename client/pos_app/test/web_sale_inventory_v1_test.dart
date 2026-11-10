import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/sync/web_sale_inventory_v1.dart';

void main() {
  const business = '11111111-1111-4111-8111-111111111111';
  const branch = '22222222-2222-4222-8222-222222222222';
  final valid = <String, Object?>{
    'contractVersion': 1,
    'globalId': '33333333-3333-4333-8333-333333333333',
    'businessGlobalId': business,
    'branchGlobalId': branch,
    'date': '2026-10-17T12:00:00Z',
    'lines': [
      {'productGlobalId': '44444444-4444-4444-8444-444444444444', 'quantity': 2,
       'lots': [{'lotGlobalId': '55555555-5555-4555-8555-555555555555', 'quantity': 2}]}
    ],
  };
  test('accepts valid strict FIFO event', () {
    expect(WebSaleInventoryV1.validate(valid, businessGlobalId: business, branchGlobalId: branch), valid);
  });
  test('rejects different branch', () {
    expect(() => WebSaleInventoryV1.validate(valid, businessGlobalId: business,
       branchGlobalId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), throwsStateError);
  });
  test('rejects unsupported version', () {
    expect(() => WebSaleInventoryV1.validate({...valid, 'contractVersion': 2},
      businessGlobalId: business, branchGlobalId: branch), throwsStateError);
  });
  test('rejects inconsistent lot sum', () {
    final lines = [{'productGlobalId': '44444444-4444-4444-8444-444444444444', 'quantity': 3,
      'lots': [{'lotGlobalId': '55555555-5555-4555-8555-555555555555', 'quantity': 2}]}];
    expect(() => WebSaleInventoryV1.validate({...valid, 'lines': lines},
      businessGlobalId: business, branchGlobalId: branch), throwsStateError);
  });
}
