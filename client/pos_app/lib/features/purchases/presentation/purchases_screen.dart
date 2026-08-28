import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/purchases/data/purchase_read_repository.dart';
import 'package:pos_app/features/purchases/data/purchase_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Compras',
    loadRows: PurchaseReadRepository(appDatabase).list,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Registrar compra', [
        'Supplier ID',
        'Supplier GID',
        'Product ID',
        'Product GID',
        'Cantidad',
        'Costo centavos',
      ]);
      if (values != null) {
        await PurchaseRepository(appDatabase).create(
          supplierId: int.parse(values[0]),
          supplierGlobalId: values[1],
          lines: [
            PurchaseLineInput(
              int.parse(values[2]),
              values[3],
              int.parse(values[4]),
              int.parse(values[5]),
            ),
          ],
        );
      }
    },
  );
}
