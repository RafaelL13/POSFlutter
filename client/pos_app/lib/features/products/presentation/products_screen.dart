import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});
  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Productos',
    subtitle: 'Administra el catálogo disponible para venta.',
    actionLabel: 'Nuevo producto',
    query: 'SELECT id,code,name,sale_price_cents,minimum_stock,active FROM products ORDER BY name',
    action: (dialogContext) async {
      final values = await textForm(dialogContext, 'Nuevo producto', [
        'Código',
        'Nombre',
        'Precio (MXN)',
        'Stock mínimo',
      ]);
      if (values != null) {
        await CatalogRepository(appDatabase).addProduct(
          code: values[0],
          name: values[1],
          salePriceCents: parseMoneyToCents(values[2]),
          minimumStock: int.tryParse(values[3]) ?? 0,
        );
      }
    },
  );
}
