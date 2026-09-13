import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

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
    resizeToAvoidBottomInset: false,
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
            labelText: 'Buscar por nombre, código, barcode o categoría',
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
                        p.code.toLowerCase().contains(query) ||
                        (p.barcode?.toLowerCase().contains(query) ?? false) ||
                        (p.categoryName?.toLowerCase().contains(query) ??
                            false),
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
                  itemBuilder: (_, index) => _ProductRow(
                    product: rows[index],
                    onEdit: () => _edit(rows[index]),
                  ),
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
    final repository = OperationalCatalogRepository(appDatabase);

    List<CatalogOption> categories;
    try {
      categories = await repository.categories();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar las categorías.')),
      );
      return;
    }

    if (!mounted) return;

    final draft = await showDialog<_ProductDraft>(
      context: context,
      builder: (_) => _ProductFormDialog(initialCategories: categories),
    );

    if (draft == null) return;

    setState(() => _saving = true);

    try {
      await CatalogRepository(appDatabase).addProduct(
        code: draft.code,
        name: draft.name,
        categoryId: draft.category.id,
        salePriceCents: draft.salePriceCents,
        minimumStock: draft.minimumStock,
        barcode: draft.barcode,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Producto creado en ${draft.category.name}. Registra una compra para agregar existencias.',
          ),
        ),
      );

      _reload();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo crear el producto. Revisa código, categoría y datos.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(ProductOverview product) async {
    final repository = OperationalCatalogRepository(appDatabase);

    List<CatalogOption> categories;

    try {
      categories = await repository.categories();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar las categorías.')),
      );

      return;
    }

    if (!mounted) return;

    final draft = await showDialog<_ProductDraft>(
      context: context,
      builder: (_) => _ProductFormDialog(
        initialCategories: categories,
        initialProduct: product,
      ),
    );

    if (draft == null || !mounted) return;

    setState(() => _saving = true);

    try {
      final completed = await runWithSpecialAuthorization(
        context: context,
        capability: Capability.productPriceChange,
        operationLabel: 'Modificar precio de producto',
        reason: 'Edición de producto ${product.name}',
        operation: (grant) => CatalogRepository(appDatabase).updateProduct(
          productId: product.id,
          code: draft.code,
          name: draft.name,
          barcode: draft.barcode,
          categoryId: draft.category.id,
          salePriceCents: draft.salePriceCents,
          minimumStock: draft.minimumStock,
          active: draft.active,
          priceAuthorizationGrant: grant,
        ),
      );

      if (!completed || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto actualizado correctamente.')),
      );

      _reload();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo actualizar el producto. Revisa datos y permisos.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _ProductDraft {
  const _ProductDraft({
    required this.code,
    required this.name,
    required this.category,
    required this.salePriceCents,
    required this.minimumStock,
    required this.active,
    this.barcode,
  });

  final String code;
  final String name;
  final String? barcode;
  final CatalogOption category;
  final int salePriceCents;
  final int minimumStock;
  final bool active;
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.initialCategories,
    this.initialProduct,
  });

  final List<CatalogOption> initialCategories;
  final ProductOverview? initialProduct;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();

  final _code = TextEditingController();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _minimumStock = TextEditingController(text: '0');

  late List<CatalogOption> _categories;
  CatalogOption? _selectedCategory;

  bool _creatingCategory = false;
  bool _active = true;

  bool get _editing => widget.initialProduct != null;

  @override
  void initState() {
    super.initState();

    _categories = [...widget.initialCategories];

    final product = widget.initialProduct;

    if (product != null) {
      _code.text = product.code;
      _name.text = product.name;
      _barcode.text = product.barcode ?? '';
      _price.text = (product.salePriceCents / 100).toStringAsFixed(2);
      _minimumStock.text = product.minimumStock.toString();
      _active = product.active;

      final matching = _categories.where(
        (category) => category.id == product.categoryId,
      );

      if (matching.isNotEmpty) {
        _selectedCategory = matching.first;
      }
    } else if (_categories.length == 1) {
      _selectedCategory = _categories.first;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _minimumStock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = keyboardInset > 0;
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= 900;

    Widget categoryField() {
      final dropdown = DropdownButtonFormField<CatalogOption>(
        key: ValueKey(
          'product-category-combobox-${_selectedCategory?.id ?? 0}',
        ),
        initialValue: _selectedCategory,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Categoría *',
          prefixIcon: Icon(Icons.category_outlined),
        ),
        items: _categories
            .map(
              (category) =>
                  DropdownMenuItem(value: category, child: Text(category.name)),
            )
            .toList(),
        onChanged: (value) {
          setState(() => _selectedCategory = value);
        },
        validator: (value) =>
            value == null ? 'Selecciona una categoría.' : null,
      );

      final createButton = TextButton.icon(
        key: const Key('product-create-category'),
        onPressed: _creatingCategory ? null : _createCategory,
        icon: const Icon(Icons.add),
        label: Text(_creatingCategory ? 'Creando…' : 'Crear categoría'),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: dropdown),
                const SizedBox(width: AppSpacing.sm),
                createButton,
              ],
            )
          else ...[
            dropdown,
            const SizedBox(height: AppSpacing.xs),
            Align(alignment: Alignment.centerLeft, child: createButton),
          ],
          if (_categories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Primero crea una categoría para poder registrar el producto.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    }

    final codeField = AppTextField(
      label: 'Código / SKU',
      controller: _code,
      required: true,
      validator: _required,
      textInputAction: TextInputAction.next,
    );

    final nameField = AppTextField(
      label: 'Nombre',
      controller: _name,
      required: true,
      validator: _required,
      textInputAction: TextInputAction.next,
    );

    final barcodeField = AppTextField(
      label: 'Código de barras',
      controller: _barcode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
    );

    final priceField = AppTextField(
      label: 'Precio de venta (MXN)',
      controller: _price,
      required: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: _validatePrice,
      textInputAction: TextInputAction.next,
    );

    final stockField = AppTextField(
      label: 'Stock mínimo',
      controller: _minimumStock,
      required: true,
      keyboardType: TextInputType.number,
      validator: _validateMinimumStock,
      textInputAction: TextInputAction.done,
    );

    final formContent = wide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: codeField),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: priceField),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: barcodeField),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: categoryField()),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: stockField),
                ],
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              codeField,
              const SizedBox(height: AppSpacing.sm),
              nameField,
              const SizedBox(height: AppSpacing.sm),
              barcodeField,
              const SizedBox(height: AppSpacing.sm),
              categoryField(),
              const SizedBox(height: AppSpacing.sm),
              priceField,
              const SizedBox(height: AppSpacing.sm),
              stockField,
            ],
          );

    return AppDialog(
      title: _editing ? 'Editar producto' : 'Nuevo producto',
      content: SizedBox(
        width: wide ? 820 : 620,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (screen.height - keyboardInset - 170).clamp(
              260.0,
              720.0,
            ),
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  formContent,
                  if (_editing) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile.adaptive(
                      key: const Key('product-active-switch'),
                      contentPadding: EdgeInsets.zero,
                      value: _active,
                      onChanged: (value) => setState(() => _active = value),
                      title: const Text('Producto activo'),
                      subtitle: Text(
                        _active ? 'Disponible para operar y vender.' : 'Oculto de la operación normal, sin borrar su historial.',
                      ),
                    ),
                  ],
                  if (!keyboardVisible) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _editing
                          ? 'Editar el producto no modifica existencias, lotes FIFO ni costos históricos.'
                          : 'Crear el producto no agrega existencias. '
                                'El stock entra mediante Compras o Entradas de inventario.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        AppPrimaryButton(
          label: _editing ? 'Guardar cambios' : 'Guardar producto',
          onPressed: _submit,
        ),
      ],
    );
  }

  Future<void> _createCategory() async {
    final values = await configuredTextForm(context, 'Nueva categoría', const [
      TextFormFieldSpec('Nombre'),
    ]);

    if (values == null || values.first.trim().isEmpty) return;

    setState(() => _creatingCategory = true);

    try {
      final globalId = await CatalogRepository(appDatabase)
          .addCategory(values.first.trim());

      final refreshed = await OperationalCatalogRepository(appDatabase)
          .categories();

      if (!mounted) return;

      final created = refreshed.where(
        (category) => category.globalId == globalId,
      );

      setState(() {
        _categories = refreshed;
        _selectedCategory = created.isNotEmpty
            ? created.first
            : (refreshed.isEmpty ? null : refreshed.first);
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear la categoría.')),
      );
    } finally {
      if (mounted) setState(() => _creatingCategory = false);
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final category = _selectedCategory;
    if (category == null) return;

    Navigator.pop(
      context,
      _ProductDraft(
        code: _code.text.trim(),
        name: _name.text.trim(),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        category: category,
        salePriceCents: parseMoneyToCents(_price.text),
        minimumStock: int.parse(_minimumStock.text.trim()),
        active: _active,
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Este campo es obligatorio.';
    }
    return null;
  }

  String? _validatePrice(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;

    try {
      if (parseMoneyToCents(value!.trim()) < 0) {
        return 'El precio no puede ser negativo.';
      }
    } catch (_) {
      return 'Ingresa un importe válido.';
    }

    return null;
  }

  String? _validateMinimumStock(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;

    final parsed = int.tryParse(value!.trim());

    if (parsed == null) return 'Ingresa un número entero.';
    if (parsed < 0) return 'No puede ser negativo.';

    return null;
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onEdit});

  final ProductOverview product;
  final VoidCallback onEdit;

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
        if (product.barcode case final barcode?) Text('Barcode: $barcode'),
        if (product.categoryName case final category?)
          Text('Categoría: $category'),
        Text('Precio: ${formatMoney(product.salePriceCents)}'),
        Text('Mínimo: ${product.minimumStock}'),
        if (product.stock != null) Text('Existencia: ${product.stock}'),
      ],
    );

    final editButton = IconButton(
      key: Key('edit-product-${product.id}'),
      tooltip: 'Editar producto',
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    editButton,
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                details,
                const SizedBox(height: AppSpacing.sm),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              status,
              const SizedBox(width: AppSpacing.xs),
              editButton,
            ],
          ),
        );
      },
    );
  }
}
