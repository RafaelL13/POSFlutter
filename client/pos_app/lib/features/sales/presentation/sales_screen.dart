import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/features/sales/data/sales_read_repository.dart';
import 'package:pos_app/features/sales/data/sales_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Ventas',
    subtitle: 'Consulta el historial de ventas del negocio.',
    actionLabel: 'Cancelar venta',
    loadRows: SalesReadRepository(appDatabase).list,
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Cancelar venta', [
        'Sale Global ID',
        'Motivo',
      ]);
      if (values != null) {
        if (!dialogContext.mounted) return false;
        await runWithSpecialAuthorization(
          context: dialogContext,
          capability: Capability.saleCancel,
          operationLabel: 'Cancelar venta',
          reason: values[1],
          operation: (grant) =>
              SalesRepository(appDatabase)
                  .cancel(values[0], values[1], authorizationGrant: grant),
        );
        return true;
      }
      return false;
    },
  );
}
