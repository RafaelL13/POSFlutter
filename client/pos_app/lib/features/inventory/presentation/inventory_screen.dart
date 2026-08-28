import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Inventario',
    loadRows: InventoryReadRepository(appDatabase).availability,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Ajuste de inventario', [
        'Product ID',
        'Cantidad (+/-)',
        'Motivo',
      ]);
      if (values != null) {
        await InventoryRepository(appDatabase).adjust(
          productId: int.parse(values[0]),
          delta: int.parse(values[1]),
          reason: values[2],
        );
      }
    },
  );
}
