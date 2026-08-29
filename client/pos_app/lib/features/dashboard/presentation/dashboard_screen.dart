import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/reports/data/report_repository.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dashboard')),
    drawer: const AppNavigationDrawer(),
    body: FutureBuilder(
      future: ReportRepository(appDatabase).today(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final metrics = snapshot.data!;
        return GridView.count(
          padding: const EdgeInsets.all(20),
          crossAxisCount: 3,
          childAspectRatio: 2.4,
          children: [
            _card('Ventas', formatMoney(metrics.salesCents)),
            _card('Operaciones', '${metrics.operations}'),
            if (metrics.fifoCostCents case final value?)
              _card('Costo FIFO', formatMoney(value)),
            if (metrics.grossProfitCents case final value?)
              _card('Utilidad bruta', formatMoney(value)),
            if (metrics.expensesCents case final value?)
              _card('Gastos', formatMoney(value)),
            if (metrics.resultCents case final value?)
              _card('Resultado', formatMoney(value)),
          ],
        );
      },
    ),
  );

  Widget _card(String title, String value) => Card(
    child: Center(
      child: ListTile(
        title: Text(title),
        subtitle: Text(value, style: const TextStyle(fontSize: 24)),
      ),
    ),
  );
}
