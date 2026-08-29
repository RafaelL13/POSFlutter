import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/cash/data/cash_read_repository.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';

class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Caja')),
    drawer: const AppNavigationDrawer(),
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
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: () async {
                  final values = await textForm(context, 'Abrir caja', [
                    'Saldo inicial centavos',
                  ]);
                  if (values != null) {
                    await CashRepository(appDatabase)
                        .open(int.parse(values[0]));
                  }
                },
                child: const Text('Abrir'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final values = await textForm(context, 'Cerrar caja', [
                    'Efectivo contado centavos',
                  ]);
                  if (values != null) {
                    await CashRepository(appDatabase)
                        .close(int.parse(values[0]));
                  }
                },
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
