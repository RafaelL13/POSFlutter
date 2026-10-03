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
  Widget build(BuildContext context) => ref
      .watch(effectiveCapabilitiesProvider)
      .when(
        data: (effective) => _buildScaffold(context, effective),
        loading: () =>
            _buildScaffold(context, const EffectiveCapabilities.denied()),
        error: (_, _) =>
            _buildScaffold(context, const EffectiveCapabilities.denied()),
      );

  Widget _buildScaffold(
    BuildContext context,
    EffectiveCapabilities effective,
  ) => Scaffold(
    appBar: AppBar(
      title: const Text('POSFlutter Admin'),
      actions: [
        if (effective.can(Capability.enrollment))
          IconButton(
            tooltip: 'Invitar dispositivo administrativo',
            onPressed: _invite,
            icon: const Icon(Icons.devices),
          ),
      ],
    ),
    drawer: AppNavigationDrawer(capabilities: effective),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<Map<String, Object?>>(
          future: repo.dashboard(),
          builder: (context, snapshot) =>
              _PosSummaryCard(snapshot: snapshot),
        ),
        if (effective.can(Capability.devicesRead))
          FutureBuilder<Map<String, Object?>>(
            future: repo.posStatus(),
            builder: (context, snapshot) =>
                _PosSyncStatusCard(snapshot: snapshot),
          ),
        if (effective.can(Capability.reportsFinancial))
          Card(
            child: ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Reportes POS'),
              subtitle: const Text(
                'Ventas reales, utilidad FIFO, caja, pagos, cancelaciones y tendencias',
              ),
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
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, index) =>
                  ListTile(title: Text(items[index].toString())),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fue posible consultar la nube.')),
        );
      }
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
          content: SelectableText(
            '${json['code'] ?? json['invitationCode']}\nExpira: ${json['expiresAt']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible generar la invitación.'),
          ),
        );
      }
    }
  }
}


class _PosSummaryCard extends StatelessWidget {
  const _PosSummaryCard({required this.snapshot});
  final AsyncSnapshot<Map<String, Object?>> snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Resumen operativo POS'),
          subtitle: Text('No fue posible consultar los datos centralizados.'),
        ),
      );
    }

    final data = snapshot.data!;
    final cards = <(String, String, IconData)>[
      (
        'Ventas netas',
        _money(data['netSalesCents']),
        Icons.payments_outlined,
      ),
      (
        'Operaciones',
        '${data['salesCount'] ?? 0}',
        Icons.receipt_long_outlined,
      ),
      (
        'Utilidad bruta',
        _money(data['grossProfitCents']),
        Icons.trending_up_outlined,
      ),
      (
        'Inventario',
        '${data['inventoryUnits'] ?? 0} piezas',
        Icons.inventory_2_outlined,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen operativo POS',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in cards)
                  SizedBox(
                    width: 220,
                    child: ListTile(
                      dense: true,
                      leading: Icon(item.$3),
                      title: Text(item.$1),
                      subtitle: Text(
                        item.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _money(Object? value) {
    final cents = value is num ? value.toInt() : 0;
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    return '$sign\${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }
}

class _PosSyncStatusCard extends StatelessWidget {
  const _PosSyncStatusCard({required this.snapshot});
  final AsyncSnapshot<Map<String, Object?>> snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Card(
        child: ListTile(
          leading: CircularProgressIndicator(),
          title: Text('Sincronización POS'),
          subtitle: Text('Consultando tablets...'),
        ),
      );
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.sync_problem_outlined),
          title: Text('Sincronización POS'),
          subtitle: Text('Estado no disponible.'),
        ),
      );
    }

    final data = snapshot.data!;
    final rawDevices = data['devices'];
    final devices = rawDevices is List
        ? rawDevices.whereType<Map>().map(Map<String, Object?>.from).toList()
        : <Map<String, Object?>>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sincronización de tablets',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip(
                  context,
                  'Actualizadas',
                  data['currentDevices'],
                  Icons.cloud_done_outlined,
                ),
                _statusChip(
                  context,
                  'Con retraso',
                  data['delayedDevices'],
                  Icons.schedule_outlined,
                ),
                _statusChip(
                  context,
                  'Desactualizadas',
                  data['staleDevices'],
                  Icons.cloud_off_outlined,
                ),
                _statusChip(
                  context,
                  'Nunca sincronizadas',
                  data['neverSyncedDevices'],
                  Icons.sync_problem_outlined,
                ),
              ],
            ),
            if (devices.isNotEmpty) ...[
              const Divider(height: 28),
              for (final device in devices.take(6))
                ListTile(
                  dense: true,
                  leading: Icon(_deviceIcon(device['freshness']?.toString())),
                  title: Text(device['deviceName']?.toString() ?? 'Dispositivo'),
                  subtitle: Text(
                    '${device['branchName'] ?? 'Sin sucursal'} · '
                    '${_freshnessText(device['freshness']?.toString(), device['ageMinutes'])}',
                  ),
                ),
              if (devices.length > 6)
                Text(
                  '+ ${devices.length - 6} dispositivos adicionales',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 8),
            Text(
              '“Actualizada” significa que la última sincronización llegó hace 2 minutos o menos; no implica conexión permanente.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _statusChip(
    BuildContext context,
    String label,
    Object? value,
    IconData icon,
  ) => Chip(
    avatar: Icon(icon, size: 18),
    label: Text('$label: ${value ?? 0}'),
  );

  static IconData _deviceIcon(String? freshness) => switch (freshness) {
    'Current' => Icons.check_circle_outline,
    'Delayed' => Icons.schedule_outlined,
    'Stale' => Icons.error_outline,
    'Never' => Icons.help_outline,
    'Inactive' => Icons.block_outlined,
    _ => Icons.devices_other_outlined,
  };

  static String _freshnessText(String? freshness, Object? ageMinutes) =>
      switch (freshness) {
        'Current' => 'actualizada hace ${ageMinutes ?? 0} min',
        'Delayed' => 'retraso de ${ageMinutes ?? 0} min',
        'Stale' => 'última sincronización hace ${ageMinutes ?? 0} min',
        'Never' => 'sin sincronización registrada',
        'Inactive' => 'dispositivo inactivo',
        _ => 'estado desconocido',
      };
}

const _cloudReadEntries =
    <({String label, String path, Capability capability})>[
      (label: 'Ventas POS', path: '/api/sales', capability: Capability.saleHistory),
      (
        label: 'Productos',
        path: '/api/products',
        capability: Capability.productRead,
      ),
      (
        label: 'Categorías',
        path: '/api/categories',
        capability: Capability.categoryRead,
      ),
      (
        label: 'Proveedores',
        path: '/api/suppliers',
        capability: Capability.supplierRead,
      ),
      (
        label: 'Existencias sincronizadas',
        path: '/api/inventory',
        capability: Capability.inventoryAvailabilityRead,
      ),
      (
        label: 'Lotes',
        path: '/api/inventory/lots',
        capability: Capability.inventoryLotsRead,
      ),
      (
        label: 'Compras',
        path: '/api/purchases',
        capability: Capability.purchaseRead,
      ),
      (
        label: 'Gastos',
        path: '/api/expenses',
        capability: Capability.expenseRead,
      ),
      (label: 'Caja', path: '/api/cash', capability: Capability.cashRead),
      (label: 'Usuarios', path: '/api/users', capability: Capability.usersRead),
      (
        label: 'Tablets / dispositivos',
        path: '/api/devices',
        capability: Capability.devicesRead,
      ),
    ];
