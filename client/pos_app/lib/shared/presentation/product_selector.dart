import 'package:flutter/material.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';

class ProductSelector extends StatelessWidget {
  const ProductSelector({
    required this.products,
    required this.onSelected,
    this.selected,
    this.onCreateProduct,
    this.requireStock = false,
    super.key,
  });

  final List<ProductOption> products;
  final ProductOption? selected;
  final ValueChanged<ProductOption?> onSelected;
  final VoidCallback? onCreateProduct;
  final bool requireStock;

  bool selectable(ProductOption product) =>
      product.active && (!requireStock || product.stock > 0);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Autocomplete<ProductOption>(
        key: const Key('product-selector'),
        initialValue: TextEditingValue(text: selected?.name ?? ''),
        displayStringForOption: (product) => product.name,
        optionsBuilder: (value) =>
            products.where((product) => product.matches(value.text)),
        onSelected: (product) {
          if (selectable(product)) onSelected(product);
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            key: const Key('product-selector-field'),
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) => onSelected(null),
            onSubmitted: (_) => onSubmitted(),
            decoration: InputDecoration(
              labelText: 'Buscar y seleccionar producto *',
              hintText: 'Nombre, código/SKU o código de barras',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: selected == null
                  ? null
                  : const Icon(Icons.check_circle_outline),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final product = options.elementAt(index);
                  final enabled = selectable(product);
                  final status = !product.active
                      ? 'Inactivo'
                      : requireStock && product.stock <= 0
                      ? 'Agotado'
                      : 'Disponible';
                  return ListTile(
                    key: Key('product-option-${product.id}'),
                    enabled: enabled,
                    onTap: enabled ? () => onSelected(product) : null,
                    title: Text(product.name),
                    subtitle: Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        Text('Código: ${product.code}'),
                        Text(product.categoryName ?? 'Sin categoría'),
                        Text(formatMoney(product.priceCents)),
                        Text('Stock: ${product.stock}'),
                        Text(status),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      if (selected != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${selected!.code} · ${selected!.categoryName ?? 'Sin categoría'} · ${formatMoney(selected!.priceCents)} · Stock ${selected!.stock}',
          key: const Key('product-selector-selection'),
        ),
      ],
      if (onCreateProduct != null)
        TextButton.icon(
          key: const Key('product-selector-create'),
          onPressed: onCreateProduct,
          icon: const Icon(Icons.add),
          label: const Text('¿No existe? Crear producto'),
        ),
    ],
  );
}
