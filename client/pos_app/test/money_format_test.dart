import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/money.dart';

void main() {
  test('formats MXN consistently with thousands and two decimals', () {
    expect(formatMoney(125000), r'$1,250.00');
    expect(formatMoney(0), r'$0.00');
  });

  test('parses common MXN inputs without floating point loss', () {
    expect(parseMoneyToCents(r'$1,250.00'), 125000);
    expect(parseMoneyToCents('19.99'), 1999);
  });
}
