import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/expenses/data/expense_read_repository.dart';
import 'package:pos_app/features/expenses/data/expense_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Gastos',
    subtitle: 'Consulta y registra egresos operativos.',
    actionLabel: 'Registrar gasto',
    loadRows: ExpenseReadRepository(appDatabase).list,
    rowTitle: expenseRowTitle,
    rowSubtitle: expenseRowSubtitle,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Nuevo gasto', [
        'Concepto',
        'Monto (MXN)',
      ]);
      if (values != null) {
        await ExpenseRepository(
          appDatabase,
        ).create(concept: values[0], amountCents: parseMoneyToCents(values[1]));
        return true;
      }
      return false;
    },
  );
}

String expenseRowTitle(Map<String, Object?> row) {
  final concept = row['concept']?.toString().trim();
  final rawDate = row['expense_date']?.toString();
  final date = rawDate == null ? null : DateTime.tryParse(rawDate)?.toLocal();
  final formattedDate = date == null
      ? 'Fecha no disponible'
      : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  return '${concept?.isNotEmpty == true ? concept : 'Gasto'} · $formattedDate';
}

String expenseRowSubtitle(Map<String, Object?> row) {
  final paymentMethod = switch (row['payment_method']?.toString()) {
    'Cash' => 'Efectivo',
    'Card' => 'Tarjeta',
    'Transfer' => 'Transferencia',
    _ => 'Método de pago no disponible',
  };
  final amount = row['amount_cents'];
  return amount is int
      ? '$paymentMethod · ${formatMoney(amount)}'
      : '$paymentMethod · Importe restringido';
}
