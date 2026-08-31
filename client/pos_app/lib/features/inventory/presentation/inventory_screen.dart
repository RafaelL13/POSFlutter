import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Inventario',
    subtitle: 'Consulta existencias y registra ajustes autorizados.',
    actionLabel: 'Ajustar inventario',
    loadRows: InventoryReadRepository(appDatabase).availability,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Ajuste de inventario', [
        'Product ID',
        'Cantidad (+/-)',
        'Motivo',
      ]);
      if (values != null) {
        if (!dialogContext.mounted) return false;
        await runWithSpecialAuthorization(
          context: dialogContext,
          capability: Capability.inventoryAdjust,
          operationLabel: 'Ajustar inventario',
          reason: values[2],
          operation: (grant) => InventoryRepository(appDatabase).adjust(
            productId: int.parse(values[0]),
            delta: int.parse(values[1]),
            reason: values[2],
            authorizationGrant: grant,
          ),
        );
        return true;
      }
      return false;
    },
  );
}
