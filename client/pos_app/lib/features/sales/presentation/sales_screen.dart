import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/sales/data/sales_read_repository.dart';
import 'package:pos_app/features/sales/data/sales_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Ventas',
    loadRows: SalesReadRepository(appDatabase).list,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Cancelar venta', [
        'Sale Global ID',
        'Motivo',
      ]);
      if (values != null) {
        await SalesRepository(appDatabase).cancel(values[0], values[1]);
      }
    },
  );
}
