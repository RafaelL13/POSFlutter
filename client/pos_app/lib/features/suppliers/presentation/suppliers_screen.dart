import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});
  @override
  Widget build(BuildContext context) => DatabaseListScreen(
    title: 'Proveedores',
    subtitle: 'Gestiona los proveedores del negocio.',
    actionLabel: 'Nuevo proveedor',
    query: 'SELECT id,name,phone,active FROM suppliers ORDER BY name',
    action: (c) async {
      final v = await textForm(c, 'Nuevo proveedor', ['Nombre']);
      if (!c.mounted) return false;
      if (!c.mounted) return false;
      if (v != null && v.first.trim().isNotEmpty) {
        return runWithSpecialAuthorization(
          context: c,
          capability: Capability.supplierWrite,
          operationLabel: 'Nuevo proveedor',
          reason: 'Alta: ${v.first.trim()}',
          operation: (grant) async {
            await CatalogRepository(appDatabase)
                .addSupplier(v.first, authorizationGrant: grant);
          },
        );
      }
      return false;
    },
  );
}
