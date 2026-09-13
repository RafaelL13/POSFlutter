import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';
import 'package:pos_app/features/purchases/data/purchase_read_repository.dart';
import 'package:pos_app/features/purchases/data/purchase_repository.dart';
import 'package:pos_app/shared/presentation/product_selector.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late Future<List<Map<String, Object?>>> _future = _load();
  bool _saving = false;
  Future<List<Map<String, Object?>>> _load() =>
      PurchaseReadRepository(appDatabase).list();
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Compras',
    subtitle: 'Registra mercancía recibida. Cada compra confirmada aumenta el stock y crea sus lotes FIFO.',
    scrollable: false,
    primaryAction: AppPrimaryButton(
      label: _saving ? 'Registrando…' : 'Nueva compra',
      icon: Icons.add_shopping_cart,
      onPressed: _saving ? null : _create,
    ),
    body: Column(
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(
                Icons.inventory_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Compras es la vía principal para agregar existencias con proveedor, costo y trazabilidad.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) return AppErrorState(onRetry: _reload);
              if (!snapshot.hasData) {
                return const AppLoadingState(label: 'Cargando compras…');
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return AppEmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message: 'Aún no hay compras. Registra la primera entrada de mercancía.',
                  action: AppPrimaryButton(
                    label: 'Registrar primera compra',
                    icon: Icons.add,
                    onPressed: _create,
                  ),
                );
              }
              return Card(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    final date = DateTime.tryParse('${row['purchase_date']}');
                    final total = row['total_cents'] as int?;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: const CircleAvatar(
                        child: Icon(Icons.local_shipping_outlined),
                      ),
                      title: Text(
                        '${row['supplier_name'] ?? 'Proveedor'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Compra #${row['id']} · ${date == null ? 'Fecha no disponible' : DateFormat('dd/MM/yyyy').format(date.toLocal())}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (total != null)
                            Text(
                              formatMoney(total),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          Text(
                            '${row['status'] == 'Confirmed' ? 'Confirmada' : row['status']}',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      final catalog = OperationalCatalogRepository(appDatabase);
      final (suppliers, products) = await (
        catalog.suppliers(),
        catalog.products(),
      ).wait;
      if (!mounted) return;
      if (suppliers.isEmpty || products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              suppliers.isEmpty
                  ? 'Primero registra al menos un proveedor.'
                  : 'Primero registra al menos un producto.',
            ),
          ),
        );
        return;
      }
      final draft = await showDialog<_PurchaseDraft>(
        context: context,
        builder: (_) =>
            _PurchaseDialog(suppliers: suppliers, products: products),
      );
      if (draft == null) return;
      await PurchaseRepository(appDatabase).create(
        supplierId: draft.supplier.id,
        supplierGlobalId: draft.supplier.globalId,
        reference: draft.reference,
        lines: draft.lines
            .map(
              (line) => PurchaseLineInput(
                line.product.id,
                line.product.globalId,
                line.quantity,
                line.unitCostCents,
              ),
            )
            .toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Compra registrada. Las existencias y lotes FIFO fueron actualizados.',
            ),
          ),
        );
        _reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo registrar la compra. Revisa los datos y permisos.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PurchaseLineDraft {
  const _PurchaseLineDraft(this.product, this.quantity, this.unitCostCents);
  final ProductOption product;
  final int quantity;
  final int unitCostCents;
  int get subtotal => quantity * unitCostCents;
}

class _PurchaseDraft {
  const _PurchaseDraft(this.supplier, this.reference, this.lines);
  final CatalogOption supplier;
  final String? reference;
  final List<_PurchaseLineDraft> lines;
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.suppliers, required this.products});
  final List<CatalogOption> suppliers;
  final List<ProductOption> products;
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late CatalogOption supplier = widget.suppliers.first;
  ProductOption? product;
  final reference = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();
  final lines = <_PurchaseLineDraft>[];
  @override
  void dispose() {
    reference.dispose();
    quantity.dispose();
    cost.dispose();
    super.dispose();
  }

  int get total => lines.fold(0, (sum, line) => sum + line.subtotal);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar compra'),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Fecha: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<CatalogOption>(
              initialValue: supplier,
              decoration: const InputDecoration(labelText: 'Proveedor *'),
              items: widget.suppliers
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.name)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => supplier = value);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Referencia o factura (opcional)',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Agregar productos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Costo unitario (MXN)',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  onPressed: _addLine,
                  tooltip: 'Agregar partida',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (lines.isEmpty)
              const Text(
                'Agrega al menos una partida.',
                textAlign: TextAlign.center,
              )
            else ...[
              for (var i = 0; i < lines.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(lines[i].product.name),
                  subtitle: Text(
                    '${lines[i].quantity} × ${formatMoney(lines[i].unitCostCents)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoney(lines[i].subtotal)),
                      IconButton(
                        onPressed: () => setState(() => lines.removeAt(i)),
                        icon: const Icon(Icons.close),
                        tooltip: 'Quitar',
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total: ${formatMoney(total)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: lines.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _PurchaseDraft(
                  supplier,
                  reference.text.trim().isEmpty ? null : reference.text.trim(),
                  List.of(lines),
                ),
              ),
        child: const Text('Confirmar compra'),
      ),
    ],
  );
  void _addLine() {
    final units = int.tryParse(quantity.text.trim());
    int unitCost;
    try {
      unitCost = parseMoneyToCents(cost.text);
    } catch (_) {
      unitCost = 0;
    }
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un producto de la lista.')),
      );
      return;
    }
    if (units == null || units <= 0 || unitCost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa cantidad y costo mayores que cero.'),
        ),
      );
      return;
    }
    setState(() {
      lines.add(_PurchaseLineDraft(product!, units, unitCost));
      quantity.text = '1';
      cost.clear();
    });
  }
}
