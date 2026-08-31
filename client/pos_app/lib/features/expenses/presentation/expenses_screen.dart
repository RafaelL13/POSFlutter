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
