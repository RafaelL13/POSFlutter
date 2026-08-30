import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/reports/data/csv_export_service.dart';
import 'package:pos_app/features/reports/data/report_repository.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Reportes',
    subtitle: 'Indicadores operativos del día.',
    scrollable: false,
    body: FutureBuilder(
      future: ReportRepository(appDatabase).today(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AppLoadingState(label: 'Calculando indicadores…');
        }
        final metrics = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              child: ListTile(
                title: const Text('Ventas hoy'),
                trailing: Text(formatMoney(metrics.salesCents)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              title: const Text('Operaciones'),
              trailing: Text('${metrics.operations}'),
            ),
            if (metrics.fifoCostCents case final value?)
              ListTile(
                title: const Text('Costo FIFO'),
                trailing: Text(formatMoney(value)),
              ),
            if (metrics.grossProfitCents case final value?)
              ListTile(
                title: const Text('Utilidad bruta'),
                trailing: Text(formatMoney(value)),
              ),
            if (metrics.expensesCents case final value?)
              ListTile(
                title: const Text('Gastos'),
                trailing: Text(formatMoney(value)),
              ),
            if (metrics.resultCents case final value?)
              ListTile(
                title: const Text('Resultado'),
                trailing: Text(formatMoney(value)),
              ),
            if (metrics.marginBasisPoints case final value?)
              ListTile(
                title: const Text('Margen'),
                trailing: Text('${(value / 100).toStringAsFixed(2)}%'),
              ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(
              label: 'Exportar ventas CSV',
              icon: Icons.download_outlined,
              onPressed: () async {
                final file = await CsvExportService(appDatabase).sales();
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('CSV: ${file.path}')));
                }
              },
            ),
          ],
        );
      },
    ),
  );
}
