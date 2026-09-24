import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/expenses/presentation/expenses_screen.dart';

void main() {
  test('expense rows use commercial labels without technical fields', () {
    final row = <String, Object?>{
      'id': 7,
      'expense_date': '2026-09-23T18:30:00.000Z',
      'concept': 'UAT gasto',
      'payment_method': 'Cash',
      'amount_cents': 12345,
    };

    expect(expenseRowTitle(row), 'UAT gasto · 23/09/2026');
    expect(expenseRowSubtitle(row), 'Efectivo · \$123.45');
    expect(expenseRowSubtitle(row), isNot(contains('amount_cents')));
    expect(expenseRowSubtitle(row), isNot(contains('payment_method')));
  });

  test('expense rows protect amounts when the capability omits them', () {
    final row = <String, Object?>{
      'expense_date': '2026-09-23T18:30:00.000Z',
      'concept': 'Gasto operativo',
      'payment_method': 'Cash',
    };

    expect(expenseRowSubtitle(row), 'Efectivo · Importe restringido');
  });
}
