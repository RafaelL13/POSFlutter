import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/money.dart';

void main() {
  test('convierte montos a centavos sin aritmética flotante', () {
    expect(parseMoneyToCents('0.10'), 10);
    expect(parseMoneyToCents(r'$1,234.56'), 123456);
    expect(parseMoneyToCents('1234,56'), 123456);
    expect(parseMoneyToCents('-2.05'), -205);
  });

  test('rechaza precisión y formatos monetarios ambiguos', () {
    expect(() => parseMoneyToCents('1.005'), throwsFormatException);
    expect(() => parseMoneyToCents(''), throwsFormatException);
    expect(() => parseMoneyToCents('abc'), throwsFormatException);
  });
}
