import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/expenses/data/expense_read_repository.dart';
import 'package:pos_app/features/expenses/data/expense_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Gastos',
    loadRows: ExpenseReadRepository(appDatabase).list,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Nuevo gasto', [
        'Concepto',
        'Monto centavos',
      ]);
      if (values != null) {
        await ExpenseRepository(appDatabase)
            .create(concept: values[0], amountCents: int.parse(values[1]));
      }
    },
  );
}
