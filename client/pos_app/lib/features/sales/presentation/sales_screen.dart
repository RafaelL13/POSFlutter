import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/sales/data/sales_read_repository.dart';
import 'package:pos_app/features/sales/data/sales_repository.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late Future<List<Map<String, Object?>>> _future = _load();
  bool _cancelling = false;
  Future<List<Map<String, Object?>>> _load() =>
      SalesReadRepository(appDatabase).list();
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Ventas',
    subtitle: 'Consulta operaciones por folio, fecha e importe.',
    scrollable: false,
    primaryAction: AppPrimaryButton(
      label: _cancelling ? 'Procesando…' : 'Cancelar venta',
      icon: Icons.cancel_outlined,
      onPressed: _cancelling ? null : _cancel,
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return AppErrorState(onRetry: _reload);
        if (!snapshot.hasData) {
          return const AppLoadingState(label: 'Cargando ventas…');
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'Aún no hay ventas registradas.',
          );
        }
        return Card(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final sale = rows[index];
              final date = DateTime.tryParse('${sale['sale_datetime']}');
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                leading: const CircleAvatar(
                  child: Icon(Icons.receipt_outlined),
                ),
                title: Text(
                  'Folio ${sale['folio']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  date == null
                      ? 'Fecha no disponible'
                      : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal()),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(sale['total_cents']! as int),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      sale['status'] == 'Completed'
                          ? 'Completada'
                          : '${sale['status']}',
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ),
  );

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      final sales = await _load();
      if (!mounted) return;
      final available = sales
          .where((sale) => sale['status'] != 'Cancelled')
          .toList();
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay ventas disponibles para cancelar.'),
          ),
        );
        return;
      }
      final request = await showDialog<_SaleCancellation>(
        context: context,
        builder: (_) => _SaleCancellationDialog(sales: available),
      );
      if (request == null || !mounted) return;
      final completed = await runWithSpecialAuthorization(
        context: context,
        capability: Capability.saleCancel,
        operationLabel: 'Cancelar venta',
        reason: request.reason,
        operation: (grant) => SalesRepository(appDatabase).cancel(
          request.sale['global_id']! as String,
          request.reason,
          authorizationGrant: grant,
        ),
      );
      if (completed && mounted) _reload();
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }
}

class _SaleCancellation {
  const _SaleCancellation(this.sale, this.reason);
  final Map<String, Object?> sale;
  final String reason;
}

class _SaleCancellationDialog extends StatefulWidget {
  const _SaleCancellationDialog({required this.sales});
  final List<Map<String, Object?>> sales;
  @override
  State<_SaleCancellationDialog> createState() =>
      _SaleCancellationDialogState();
}

class _SaleCancellationDialogState extends State<_SaleCancellationDialog> {
  Map<String, Object?>? selected;
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'Cancelar venta',
    destructive: true,
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<Map<String, Object?>>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Venta *'),
            items: widget.sales.map((sale) {
              final date = DateTime.tryParse('${sale['sale_datetime']}');
              final label =
                  'Folio ${sale['folio']} · ${date == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal())} · ${formatMoney(sale['total_cents']! as int)}';
              return DropdownMenuItem(
                value: sale,
                child: Text(label, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (value) => setState(() => selected = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo *'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Conservar venta'),
      ),
      FilledButton.tonal(
        onPressed: _submit,
        child: const Text('Continuar autorización'),
      ),
    ],
  );
  void _submit() {
    if (selected == null || reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una venta e indica el motivo.'),
        ),
      );
      return;
    }
    Navigator.pop(context, _SaleCancellation(selected!, reason.text.trim()));
  }
}
