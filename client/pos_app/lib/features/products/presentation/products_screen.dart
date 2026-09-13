import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  late Future<List<ProductOverview>> _future = _load();
  bool _saving = false;
  Future<List<ProductOverview>> _load() =>
      OperationalCatalogRepository(appDatabase).productOverview();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Productos',
    subtitle: 'Administra el catálogo, precios de venta y alertas de stock.',
    scrollable: false,
    primaryAction: AppPrimaryButton(
      label: _saving ? 'Guardando…' : 'Nuevo producto',
      icon: Icons.add,
      onPressed: _saving ? null : _create,
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
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 600)
                      Text(
                        'Crear un producto no agrega existencias',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    const Text(
                      'Crear el producto no agrega stock. Registra una compra o entrada para aumentarlo.',
                    ),
                    if (MediaQuery.sizeOf(context).width >= 600) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          TextButton.icon(
                            onPressed: () => context.go('/purchases'),
                            icon: const Icon(Icons.shopping_cart_checkout),
                            label: const Text('Ir a Compras'),
                          ),
                          TextButton.icon(
                            onPressed: () => context.go('/inventory'),
                            icon: const Icon(Icons.warehouse_outlined),
                            label: const Text('Ver inventario'),
                          ),
                        ],
                      ),
                    ],
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
            labelText: 'Buscar por código o nombre',
            suffixIcon: Icon(Icons.manage_search),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: FutureBuilder<List<ProductOverview>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) return AppErrorState(onRetry: _reload);
              if (!snapshot.hasData) {
                return const AppLoadingState(label: 'Cargando productos…');
              }
              final query = _search.text.trim().toLowerCase();
              final rows = snapshot.data!
                  .where(
                    (p) =>
                        query.isEmpty ||
                        p.name.toLowerCase().contains(query) ||
                        p.code.toLowerCase().contains(query),
                  )
                  .toList();
              if (rows.isEmpty) {
                return AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: query.isEmpty
                      ? 'Aún no hay productos. Crea el primero para comenzar tu catálogo.'
                      : 'No encontramos productos con esa búsqueda.',
                  action: query.isEmpty
                      ? AppPrimaryButton(
                          label: 'Crear primer producto',
                          icon: Icons.add,
                          onPressed: _create,
                        )
                      : null,
                );
              }
              return Card(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => _ProductRow(product: rows[index]),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  void _reload() => setState(() => _future = _load());
  Future<void> _create() async {
    final values = await configuredTextForm(context, 'Nuevo producto', const [
      TextFormFieldSpec('Código'),
      TextFormFieldSpec('Nombre'),
      TextFormFieldSpec('Precio de venta (MXN)', numeric: true),
      TextFormFieldSpec('Stock mínimo', numeric: true, allowZero: true),
    ]);
    if (values == null) return;
    setState(() => _saving = true);
    try {
      await CatalogRepository(appDatabase).addProduct(
        code: values[0],
        name: values[1],
        salePriceCents: parseMoneyToCents(values[2]),
        minimumStock: int.parse(values[3]),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Producto creado. Registra una compra para agregar existencias.',
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
              'No se pudo crear el producto. Revisa el código y los datos.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});
  final ProductOverview product;
  @override
  Widget build(BuildContext context) {
    final low = product.stock != null && product.stock! <= product.minimumStock;
    final status = AppStatusChip(
      label: !product.active
          ? 'Inactivo'
          : low
          ? 'Stock bajo'
          : 'Activo',
      status: !product.active
          ? AppStatus.inactive
          : low
          ? AppStatus.warning
          : AppStatus.active,
    );
    final details = Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      children: [
        Text('Código: ${product.code}'),
        Text('Precio: ${formatMoney(product.salePriceCents)}'),
        if (product.stock != null) Text('Existencia: ${product.stock}'),
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
                  product.name,
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
            child: Text(product.name.characters.first.toUpperCase()),
          ),
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: details,
          trailing: status,
        );
      },
    );
  }
}
