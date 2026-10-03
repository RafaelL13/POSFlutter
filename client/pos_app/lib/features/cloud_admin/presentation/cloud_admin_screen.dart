import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
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
      title: const Text('Administración remota'),
      actions: [
        if (effective.can(Capability.enrollment))
          IconButton(
            tooltip: 'Invitar dispositivo',
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
          builder: (context, snapshot) => Card(
            child: ListTile(
              title: const Text('Dashboard cloud'),
              subtitle: Text(
                snapshot.hasData
                    ? snapshot.data.toString()
                    : snapshot.hasError
                    ? 'No disponible'
                    : 'Cargando...',
              ),
            ),
          ),
        ),
        if (effective.can(Capability.reportsFinancial))
          Card(
            child: ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Reportes remotos'),
              subtitle: const Text(
                'Ventas, utilidad, inventario, compras, gastos, caja y tendencias',
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
                onTap: () => entry.path == '/api/devices'
                    ? _showDevices(effective)
                    : _show(entry.label, entry.path),
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

  Future<void> _showDevices(EffectiveCapabilities effective) async {
    try {
      final items = await repo.list('/api/devices');
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final colorScheme = theme.colorScheme;

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Icon(Icons.devices_other_outlined, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Expanded(child: Text('Dispositivos')),
              ],
            ),
            content: SizedBox(
              width: 720,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: items.isEmpty
                    ? const _EmptyDevicesView()
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, index) =>
                            _DeviceCard(item: items[index]),
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
              if (effective.can(Capability.enrollment))
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _invite();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Conectar nuevo dispositivo'),
                ),
            ],
          );
        },
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible consultar los dispositivos.'),
        ),
      );
    }
  }

  Future<void> _invite() async {
    final mode = await showDialog<DeviceMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tipo de dispositivo'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('Terminal de venta'),
                subtitle: const Text(
                  'Opera el POS y puede continuar vendiendo sin Internet después de la configuración inicial.',
                ),
                onTap: () =>
                    Navigator.pop(dialogContext, DeviceMode.pointOfSale),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Solo administración'),
                subtitle: const Text(
                  'Permite las funciones administrativas autorizadas y no habilita operaciones de venta.',
                ),
                onTap: () =>
                    Navigator.pop(dialogContext, DeviceMode.adminReadOnly),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (mode == null || !mounted) return;

    try {
      final json = await repo.createInvitation(mode: mode);
      if (!mounted) return;

      final returnedMode =
          DeviceMode.tryParse(json['mode']?.toString()) ?? mode;

      final rawCode = (json['code'] ?? json['token'] ?? '')
          .toString()
          .trim()
          .toUpperCase()
          .replaceAll('-', '')
          .replaceAll(' ', '');

      final invitationCode = rawCode.length == 8
          ? '${rawCode.substring(0, 4)}-${rawCode.substring(4)}'
          : rawCode;

      final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '')
          ?.toLocal();

      String two(int value) => value.toString().padLeft(2, '0');

      final expirationText = expiresAt == null
          ? 'Código temporal de un solo uso.'
          : 'Expira el ${two(expiresAt.day)}/${two(expiresAt.month)}/'
                '${expiresAt.year} a las ${two(expiresAt.hour)}:'
                '${two(expiresAt.minute)}';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.devices_other_outlined),
              SizedBox(width: 12),
              Expanded(child: Text('Código de invitación')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  returnedMode == DeviceMode.pointOfSale
                      ? 'Terminal de venta'
                      : 'Solo administración',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    invitationCode,
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(expirationText, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Text(
                  'En la nueva tablet:',
                  style: Theme.of(dialogContext).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Instala POSFlutter.\n'
                  '2. Selecciona "Conectar a negocio existente".\n'
                  '3. Captura este código y las credenciales de un administrador.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: invitationCode.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: invitationCode),
                      );

                      if (!dialogContext.mounted) return;

                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Código copiado.')),
                      );
                    },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copiar código'),
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

final class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.item});

  final Object? item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final json = item is Map
        ? Map<String, Object?>.from(item as Map)
        : const <String, Object?>{};

    final name = _value(json, 'name', fallback: 'Dispositivo');
    final mode = _value(json, 'mode');
    final active = _boolValue(json['active']);
    final lastSync = _value(json, 'lastSyncAt');

    final isPos = mode == 'PointOfSale';
    final modeLabel = isPos ? 'Terminal de venta' : 'Solo administración';

    final icon = isPos
        ? Icons.point_of_sale_outlined
        : Icons.admin_panel_settings_outlined;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(modeLabel, style: theme.textTheme.bodyMedium),
                  if (lastSync.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.sync,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Última sincronización: ${_formatDate(lastSync)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StatusBadge(active: active),
          ],
        ),
      ),
    );
  }

  static String _value(
    Map<String, Object?> json,
    String key, {
    String fallback = '',
  }) {
    final value = json[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  static bool _boolValue(Object? value) =>
      value == true || value?.toString().toLowerCase() == 'true';

  static String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final background = active
        ? colorScheme.primaryContainer
        : colorScheme.errorContainer;

    final foreground = active
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.cancel_outlined,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Activo' : 'Inactivo',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

final class _EmptyDevicesView extends StatelessWidget {
  const _EmptyDevicesView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_other_outlined,
            size: 52,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Aún no hay dispositivos',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Conecta una tablet para comenzar a operar en esta sucursal.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

const _cloudReadEntries =
    <({String label, String path, Capability capability})>[
      (label: 'Ventas', path: '/api/sales', capability: Capability.saleHistory),
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
        label: 'Inventario',
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
        label: 'Dispositivos',
        path: '/api/devices',
        capability: Capability.devicesRead,
      ),
    ];
