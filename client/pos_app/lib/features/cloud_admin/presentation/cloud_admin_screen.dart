import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/cloud_admin/data/cloud_admin_repository.dart';

class CloudAdminScreen extends StatefulWidget {
  const CloudAdminScreen({super.key});

  @override
  State<CloudAdminScreen> createState() => _CloudAdminScreenState();
}

class _CloudAdminScreenState extends State<CloudAdminScreen> {
  late final CloudAdminRepository repo = CloudAdminRepository(cloudApiClient);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Administración remota'),
          actions: [IconButton(tooltip: 'Invitar dispositivo administrativo', onPressed: _invite, icon: const Icon(Icons.devices))],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FutureBuilder<Map<String, Object?>>(
              future: repo.dashboard(),
              builder: (context, snapshot) => Card(
                child: ListTile(
                  title: const Text('Dashboard cloud'),
                  subtitle: Text(snapshot.hasData ? snapshot.data.toString() : snapshot.hasError ? 'No disponible' : 'Cargando...'),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Reportes remotos'),
                subtitle: const Text('Ventas, utilidad, inventario, compras, gastos, caja y tendencias'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/cloud-admin/reports'),
              ),
            ),
            for (final entry in const {
              'Ventas': '/api/sales',
              'Productos': '/api/products',
              'Categorías': '/api/categories',
              'Proveedores': '/api/suppliers',
              'Inventario': '/api/inventory',
              'Lotes': '/api/inventory/lots',
              'Compras': '/api/purchases',
              'Gastos': '/api/expenses',
              'Caja': '/api/cash',
              'Usuarios': '/api/users',
            }.entries)
              Card(
                child: ListTile(
                  title: Text(entry.key),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _show(entry.key, entry.value),
                ),
              ),
          ],
        ),
      );

  Future<void> _show(String title, String path) async {
    try {
      final items = await repo.list(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 650,
            height: 450,
            child: ListView.builder(itemCount: items.length, itemBuilder: (_, index) => ListTile(title: Text(items[index].toString()))),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar'))],
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No fue posible consultar la nube.')));
    }
  }

  Future<void> _invite() async {
    try {
      final json = await repo.createInvitation();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Código de invitación'),
          content: SelectableText('${json['code'] ?? json['invitationCode']}\nExpira: ${json['expiresAt']}'),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar'))],
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No fue posible generar la invitación.')));
    }
  }
}
