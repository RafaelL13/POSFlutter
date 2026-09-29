import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_repository.dart';
import 'package:pos_app/shared/presentation/product_selector.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  late Future<List<Map<String, Object?>>> _future = _load();
  bool _saving = false;
  Future<List<Map<String, Object?>>> _load() =>
      InventoryReadRepository(appDatabase).availability();
  void _reload() => setState(() => _future = _load());
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Inventario',
    subtitle: 'Consulta existencias, valor y último movimiento por producto.',
    scrollable: false,
    primaryAction: AppPrimaryButton(
      label: _saving ? 'Guardando…' : 'Ajustar inventario',
      icon: Icons.tune,
      onPressed: _saving ? null : _adjust,
    ),
    body: Column(
      children: [
        AppCard(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600
                ? AppSpacing.sm
                : AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.route_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 600)
                      Text(
                        '¿De dónde salen las existencias?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    const Text(
                      'Compras agrega stock; ventas descuenta por FIFO. Los ajustes requieren autorización.',
                    ),
                    if (MediaQuery.sizeOf(context).width >= 600) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TextButton.icon(
                        onPressed: () => context.go('/purchases'),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Registrar compra o entrada'),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: _showCentralTransferHistory,
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      label: const Text('Transferencias recibidas'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar producto o código',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) return AppErrorState(onRetry: _reload);
              if (!snapshot.hasData) {
                return const AppLoadingState(label: 'Calculando inventario…');
              }
              final query = _search.text.trim().toLowerCase();
              final rows = snapshot.data!
                  .where(
                    (row) =>
                        query.isEmpty ||
                        '${row['name']}'.toLowerCase().contains(query) ||
                        '${row['code']}'.toLowerCase().contains(query),
                  )
                  .toList();
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.warehouse_outlined,
                  message: 'No hay productos para mostrar en inventario.',
                );
              }
              return Card(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => _InventoryRow(row: rows[index]),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Future<void> _showCentralTransferHistory() async {
    await showDialog<void>(
      context: context,
      builder: (_) => CentralTransferHistoryDialog(
        loader: () =>
            InventoryReadRepository(appDatabase).centralTransferHistory(),
      ),
    );
  }

  Future<void> _adjust() async {
    setState(() => _saving = true);
    try {
      final products = await OperationalCatalogRepository(appDatabase)
          .products();
      if (!mounted) return;
      if (products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero registra un producto.')),
        );
        return;
      }
      final draft = await showDialog<_AdjustmentDraft>(
        context: context,
        builder: (_) => _AdjustmentDialog(products: products),
      );
      if (draft == null || !mounted) return;
      final completed = await runWithSpecialAuthorization(
        context: context,
        capability: Capability.inventoryAdjust,
        operationLabel: 'Ajustar inventario',
        reason: draft.reason,
        operation: (grant) => InventoryRepository(appDatabase).adjust(
          productId: draft.product.id,
          delta: draft.delta,
          reason: draft.reason,
          authorizationGrant: grant,
        ),
      );
      if (completed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajuste registrado correctamente.')),
        );
        _reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo completar el ajuste. Revisa los datos y permisos.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.row});
  final Map<String, Object?> row;
  @override
  Widget build(BuildContext context) {
    final stock = row['stock']! as int;
    final minimum = row['minimum_stock']! as int;
    final low = stock <= minimum;
    final rawDate = row['last_movement'] as String?;
    final date = rawDate == null ? null : DateTime.tryParse(rawDate);
    final status = AppStatusChip(
      label: low ? (stock == 0 ? 'Sin stock' : 'Stock bajo') : 'Disponible',
      status: low ? AppStatus.warning : AppStatus.active,
    );
    final details = Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      children: [
        Text('Código: ${row['code']}'),
        Text('Existencia: $stock'),
        if (row['value_cents'] case final int value)
          Text('Valor: ${formatMoney(value)}'),
        Text(
          date == null
              ? 'Sin movimientos'
              : 'Último movimiento: ${DateFormat('dd/MM/yyyy').format(date.toLocal())}',
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                details,
                const SizedBox(height: AppSpacing.xs),
                status,
              ],
            ),
          );
        }
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: CircleAvatar(
            child: Text('${row['name']}'.characters.first.toUpperCase()),
          ),
          title: Text(
            '${row['name']}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: details,
          trailing: status,
        );
      },
    );
  }
}

class CentralTransferHistoryDialog extends StatefulWidget {
  const CentralTransferHistoryDialog({super.key, required this.loader});

  final Future<List<CentralTransferHistoryItem>> Function() loader;

  @override
  State<CentralTransferHistoryDialog> createState() =>
      _CentralTransferHistoryDialogState();
}

class _CentralTransferHistoryDialogState
    extends State<CentralTransferHistoryDialog> {
  late Future<List<CentralTransferHistoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() {
    setState(() => _future = widget.loader());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.move_to_inbox_outlined),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: Text('Transferencias recibidas')),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
      child: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: FutureBuilder<List<CentralTransferHistoryItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppErrorState(onRetry: _reload);
            }

            if (!snapshot.hasData) {
              return const AppLoadingState(label: 'Cargando transferencias…');
            }

            final rows = snapshot.data!;

            if (rows.isEmpty) {
              return const AppEmptyState(
                icon: Icons.move_to_inbox_outlined,
                message: 'No hay transferencias centrales recibidas en esta sucursal.',
              );
            }

            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) =>
                  _CentralTransferHistoryRow(item: rows[index]),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}

class _CentralTransferHistoryRow extends StatelessWidget {
  const _CentralTransferHistoryRow({required this.item});

  final CentralTransferHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(item.status);
    final localDate = item.transferDate.toLocal();
    final shortId = item.transferGlobalId.length <= 8
        ? item.transferGlobalId
        : item.transferGlobalId.substring(0, 8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transferencia $shortId',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              AppStatusChip(
                label: presentation.label,
                status: presentation.status,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            children: [
              Text(DateFormat('dd/MM/yyyy HH:mm').format(localDate)),
              Text('${item.productCount} productos'),
              Text('${item.totalQuantity} unidades'),
              if (item.retryCount > 0) Text('Reintentos: ${item.retryCount}'),
            ],
          ),
          if (item.errorCategory != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Sincronización: ${item.errorCategory}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  static ({String label, AppStatus status}) _presentationFor(
    CentralTransferHistoryStatus status,
  ) => switch (status) {
    CentralTransferHistoryStatus.confirmed => (
      label: 'Confirmada',
      status: AppStatus.active,
    ),
    CentralTransferHistoryStatus.pendingAck => (
      label: 'Pendiente de envío',
      status: AppStatus.warning,
    ),
    CentralTransferHistoryStatus.syncing => (
      label: 'Enviando',
      status: AppStatus.warning,
    ),
    CentralTransferHistoryStatus.retrying => (
      label: 'Reintentando',
      status: AppStatus.warning,
    ),
    CentralTransferHistoryStatus.attentionRequired => (
      label: 'Requiere atención',
      status: AppStatus.warning,
    ),
    CentralTransferHistoryStatus.localOnly => (
      label: 'Aplicada localmente',
      status: AppStatus.warning,
    ),
  };
}

class _AdjustmentDraft {
  const _AdjustmentDraft(this.product, this.delta, this.reason);
  final ProductOption product;
  final int delta;
  final String reason;
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({required this.products});
  final List<ProductOption> products;
  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  ProductOption? product;
  final quantity = TextEditingController();
  final reason = TextEditingController();
  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajuste autorizado de inventario'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProductSelector(
            products: widget.products,
            selected: product,
            onSelected: (value) => setState(() => product = value),
            onCreateProduct: () {
              Navigator.pop(context);
              context.go('/products');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: quantity,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
              labelText: 'Cantidad (+ entrada / − salida)',
              helperText: 'Ejemplo: 5 para agregar o -2 para retirar.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo del ajuste'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Continuar autorización'),
      ),
    ],
  );
  void _submit() {
    final delta = int.tryParse(quantity.text.trim());
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un producto de la lista.')),
      );
      return;
    }
    if (delta == null || delta == 0 || reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una cantidad distinta de cero y el motivo.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _AdjustmentDraft(product!, delta, reason.text.trim()),
    );
  }
}
