import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/features/cloud_admin/data/cloud_admin_repository.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';

class CloudAdminScreen extends ConsumerStatefulWidget {
  const CloudAdminScreen({super.key});

  @override
  ConsumerState<CloudAdminScreen> createState() => _CloudAdminScreenState();
}

class _CloudAdminScreenState extends ConsumerState<CloudAdminScreen> {
  late final CloudAdminRepository repo = CloudAdminRepository(cloudApiClient);

  @override
  Widget build(BuildContext context) => ref.watch(effectiveCapabilitiesProvider).when(
      data: (effective) => _buildScaffold(context, effective),
      loading: () => _buildScaffold(context, const EffectiveCapabilities.denied()),
      error: (_, _) => _buildScaffold(context, const EffectiveCapabilities.denied()),
    );

  Widget _buildScaffold(
    BuildContext context,
    EffectiveCapabilities effective,
  ) => Scaffold(
        appBar: AppBar(
          title: const Text('Administración remota'),
          actions: [
            if (effective.can(Capability.enrollment))
              IconButton(tooltip: 'Invitar dispositivo administrativo', onPressed: _invite, icon: const Icon(Icons.devices)),
          ],
        ),
        drawer: AppNavigationDrawer(capabilities: effective),
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
            if (effective.can(Capability.reportsFinancial))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('Reportes remotos'),
                  subtitle: const Text('Ventas, utilidad, inventario, compras, gastos, caja y tendencias'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/cloud-admin/reports'),
                ),
              ),
            for (final entry in _cloudReadEntries)
              if (effective.can(entry.capability))
              Card(
                child: ListTile(
                  title: Text(entry.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _show(entry.label, entry.path),
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

const _cloudReadEntries = <({String label, String path, Capability capability})>[
  (label: 'Ventas', path: '/api/sales', capability: Capability.saleHistory),
  (label: 'Productos', path: '/api/products', capability: Capability.productRead),
  (label: 'Categorías', path: '/api/categories', capability: Capability.categoryRead),
  (label: 'Proveedores', path: '/api/suppliers', capability: Capability.supplierRead),
  (label: 'Inventario', path: '/api/inventory', capability: Capability.inventoryAvailabilityRead),
  (label: 'Lotes', path: '/api/inventory/lots', capability: Capability.inventoryLotsRead),
  (label: 'Compras', path: '/api/purchases', capability: Capability.purchaseRead),
  (label: 'Gastos', path: '/api/expenses', capability: Capability.expenseRead),
  (label: 'Caja', path: '/api/cash', capability: Capability.cashRead),
  (label: 'Usuarios', path: '/api/users', capability: Capability.usersRead),
  (label: 'Dispositivos', path: '/api/devices', capability: Capability.devicesRead),
];
