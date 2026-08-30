import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/cash/data/cash_read_repository.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';

class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Caja',
    subtitle: 'Consulta sesiones y controla la operación de efectivo.',
    scrollable: false,
    body: Column(
      children: [
        Expanded(
          child: DatabaseListScreen(
            title: 'Sesiones',
            loadRows: CashReadRepository(appDatabase).sessions,
            showNavigation: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Wrap(
            spacing: 12,
            children: [
              AppPrimaryButton(
                label: 'Abrir caja',
                icon: Icons.lock_open_outlined,
                onPressed: () async {
                  final values = await textForm(context, 'Abrir caja', [
                    'Saldo inicial (MXN)',
                  ]);
                  if (values != null) {
                    await CashRepository(appDatabase)
                        .open(parseMoneyToCents(values[0]));
                  }
                },
              ),
              AppSecondaryButton(
                label: 'Cerrar caja',
                icon: Icons.lock_outline,
                onPressed: () async {
                  final values = await textForm(context, 'Cerrar caja', [
                    'Efectivo contado (MXN)',
                  ]);
                  if (values != null) {
                    if (!context.mounted) return;
                    await runWithSpecialAuthorization(
                      context: context,
                      capability: Capability.cashCloseWithDifference,
                      operationLabel: 'Cerrar caja con diferencia',
                      reason: 'Cierre de caja con diferencia',
                      operation: (grant) => CashRepository(appDatabase).close(
                        parseMoneyToCents(values[0]),
                        authorizationGrant: grant,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
