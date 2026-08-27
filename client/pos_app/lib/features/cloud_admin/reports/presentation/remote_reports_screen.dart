import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_repository.dart';

class RemoteReportsScreen extends StatefulWidget {
  const RemoteReportsScreen({super.key});

  @override
  State<RemoteReportsScreen> createState() => _RemoteReportsScreenState();
}

class _RemoteReportsScreenState extends State<RemoteReportsScreen> {
  late final RemoteReportRepository _repository = RemoteReportRepository(cloudApiClient);
  RemoteReportFilter _filter = RemoteReportFilter.forPreset(ReportPreset.thisMonth);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reportes remotos')),
        body: RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _PeriodSelector(filter: _filter, onChanged: _changeFilter),
              const SizedBox(height: 16),
              FutureBuilder<RemoteSummary>(
                future: _repository.summary(_filter),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
                  if (snapshot.hasError) return _RemoteError(error: snapshot.error);
                  return _SummaryGrid(summary: snapshot.data!);
                },
              ),
              const SizedBox(height: 20),
              Text('Detalle', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, childAspectRatio: 2.5, mainAxisSpacing: 10, crossAxisSpacing: 10),
                itemCount: RemoteReportKind.values.length,
                itemBuilder: (_, index) {
                  final kind = RemoteReportKind.values[index];
                  return Card(
                    child: ListTile(
                      title: Text(kind.title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/cloud-admin/reports/${kind.name}'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text('Los filtros de día se calculan en la zona horaria del dispositivo y se envían al servidor como instantes UTC. El modelo actual de Business todavía no almacena una zona horaria propia.'),
            ],
          ),
        ),
      );

  Future<void> _changeFilter(ReportPreset preset) async {
    if (preset != ReportPreset.custom) {
      setState(() => _filter = RemoteReportFilter.forPreset(preset));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 1), initialDateRange: DateTimeRange(start: now, end: now));
    if (range != null) setState(() => _filter = RemoteReportFilter.custom(range.start, range.end));
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});
  final RemoteSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Ventas brutas', formatMoney(summary.grossSalesCents)),
      ('Ventas netas', formatMoney(summary.netSalesCents)),
      ('Operaciones', '${summary.salesCount}'),
      ('Unidades', '${summary.unitsSold}'),
      ('Ticket promedio', formatMoney(summary.averageTicketCents)),
      ('Costo FIFO', formatMoney(summary.fifoCostCents)),
      ('Utilidad bruta', formatMoney(summary.grossProfitCents)),
      ('Margen', '${summary.grossMarginPercent.toStringAsFixed(2)}%'),
      ('Gastos', formatMoney(summary.expensesCents)),
      ('Resultado', formatMoney(summary.resultAfterExpensesCents)),
      ('Cancelaciones', '${summary.cancelledSalesCount} · ${formatMoney(summary.cancelledSalesCents)} · ${summary.cancellationRatePercent.toStringAsFixed(2)}%'),
      ('Existencia', '${summary.inventoryUnits} piezas'),
      ('Inventario valorizado', formatMoney(summary.inventoryValueCents)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, childAspectRatio: 2.3, mainAxisSpacing: 10, crossAxisSpacing: 10),
      itemCount: items.length,
      itemBuilder: (_, i) => Card(child: ListTile(title: Text(items[i].$1), subtitle: Text(items[i].$2, style: Theme.of(context).textTheme.titleLarge))),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.filter, required this.onChanged});
  final RemoteReportFilter filter;
  final ValueChanged<ReportPreset> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ReportPreset.values
            .map((preset) => ChoiceChip(label: Text(RemoteReportFilter.forPreset(preset).label), selected: filter.preset == preset, onSelected: (_) => onChanged(preset)))
            .toList(),
      );
}

class _RemoteError extends StatelessWidget {
  const _RemoteError({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final message = error is CloudApiException
        ? (error as CloudApiException).message
        : 'No fue posible consultar los reportes remotos.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Los reportes remotos requieren conexión. Un dispositivo PointOfSale puede seguir usando la sección Reportes locales sin depender de la nube.'),
          ],
        ),
      ),
    );
  }
}
