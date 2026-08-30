import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/dashboard/data/home_repository.dart';
import 'package:pos_app/sync/presentation/sync_status_panel.dart';
import 'package:pos_app/sync/sync_health.dart';

final class HomeAction {
  const HomeAction({
    required this.title,
    required this.icon,
    required this.route,
    required this.requiredCapabilities,
  });

  final String title;
  final IconData icon;
  final String route;
  final Set<Capability> requiredCapabilities;
}

const homeActions = <HomeAction>[
  HomeAction(
    title: 'Nueva venta',
    icon: Icons.point_of_sale,
    route: '/pos',
    requiredCapabilities: {Capability.saleCreate},
  ),
  HomeAction(
    title: 'Ventas',
    icon: Icons.receipt_long_outlined,
    route: '/sales',
    requiredCapabilities: {Capability.saleHistory},
  ),
  HomeAction(
    title: 'Caja',
    icon: Icons.account_balance_wallet_outlined,
    route: '/cash',
    requiredCapabilities: {Capability.cashRead},
  ),
  HomeAction(
    title: 'Inventario',
    icon: Icons.warehouse_outlined,
    route: '/inventory',
    requiredCapabilities: {Capability.inventoryAvailabilityRead},
  ),
  HomeAction(
    title: 'Productos',
    icon: Icons.inventory_2_outlined,
    route: '/products',
    requiredCapabilities: {Capability.productRead},
  ),
  HomeAction(
    title: 'Compras',
    icon: Icons.shopping_cart_outlined,
    route: '/purchases',
    requiredCapabilities: {Capability.purchaseRead},
  ),
  HomeAction(
    title: 'Gastos',
    icon: Icons.payments_outlined,
    route: '/expenses',
    requiredCapabilities: {Capability.expenseRead},
  ),
  HomeAction(
    title: 'Reportes',
    icon: Icons.analytics_outlined,
    route: '/reports',
    requiredCapabilities: {Capability.reportsOperational},
  ),
  HomeAction(
    title: 'Usuarios',
    icon: Icons.people_outline,
    route: '/users',
    requiredCapabilities: {Capability.usersRead},
  ),
  HomeAction(
    title: 'Administración nube',
    icon: Icons.cloud_outlined,
    route: '/cloud-admin',
    requiredCapabilities: {Capability.cloudAdminRead},
  ),
  HomeAction(
    title: 'Respaldos',
    icon: Icons.backup_outlined,
    route: '/backup',
    requiredCapabilities: {Capability.backupCreate},
  ),
];

List<HomeAction> visibleHomeActions(EffectiveCapabilities capabilities) =>
    homeActions
        .where(
          (action) =>
              action.requiredCapabilities.every(capabilities.can) &&
              RouteAuthorization.canOpen(action.route, capabilities),
        )
        .toList(growable: false);

class HomeContent extends StatelessWidget {
  const HomeContent({required this.summary, this.syncSummary, super.key});
  final HomeSummary summary;
  final SyncSummary? syncSummary;

  @override
  Widget build(BuildContext context) {
    final capabilities = summary.capabilities;
    final actions = visibleHomeActions(capabilities);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final horizontal = wide ? 32.0 : 16.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 32),
          children: [
            _HomeHeader(summary: summary),
            const SizedBox(height: 20),
            if (capabilities.can(Capability.saleCreate)) ...[
              _PrimarySaleAction(onTap: () => context.go('/pos')),
              const SizedBox(height: 20),
            ],
            _KpiGrid(summary: summary, wide: wide),
            const SizedBox(height: 24),
            Text(
              'Accesos rápidos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _QuickActionGrid(actions: actions, wide: wide),
            const SizedBox(height: 24),
            Text(
              'Estado operativo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Card(child: SyncStatusPanel(summary: syncSummary)),
          ],
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.summary});
  final HomeSummary summary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Hola, ${summary.userName}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text('${summary.branchName} · ${_roleLabel(summary.capabilities.role)}'),
      if (summary.deviceMode == 'AdminReadOnly')
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Chip(
            avatar: Icon(Icons.visibility_outlined),
            label: Text('Dispositivo en modo consulta'),
          ),
        ),
    ],
  );

  String _roleLabel(AppRole? role) => switch (role) {
    AppRole.administrator => 'Administrador',
    AppRole.manager => 'Gerente',
    AppRole.supervisor => 'Supervisor',
    AppRole.seller => 'Vendedor',
    null => 'Acceso restringido',
  };
}

class _PrimarySaleAction extends StatelessWidget {
  const _PrimarySaleAction({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const Key('home-primary-sale'),
    onPressed: onTap,
    icon: const Icon(Icons.point_of_sale, size: 30),
    label: const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Text('Nueva venta', style: TextStyle(fontSize: 20)),
    ),
  );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary, required this.wide});
  final HomeSummary summary;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final metrics = summary.metrics;
    final items = <(String, String, IconData)>[
      if (metrics != null)
        ('Ventas de hoy', formatMoney(metrics.salesCents), Icons.today),
      if (metrics != null)
        ('Operaciones', '${metrics.operations}', Icons.receipt_long),
      if (summary.hasOpenCash case final open?)
        (
          'Caja',
          open ? 'Abierta' : 'Sin caja abierta',
          Icons.account_balance_wallet_outlined,
        ),
      if (summary.inventoryUnits case final units?)
        ('Inventario disponible', '$units unidades', Icons.warehouse_outlined),
      if (metrics?.grossProfitCents case final value?)
        ('Utilidad bruta', formatMoney(value), Icons.trending_up),
      if (metrics?.marginBasisPoints case final value?)
        ('Margen', '${(value / 100).toStringAsFixed(2)} %', Icons.percent),
      if (metrics?.expensesCents case final value?)
        ('Gastos de hoy', formatMoney(value), Icons.payments_outlined),
      if (summary.inventoryValueCents case final value?)
        ('Inventario valorizado', formatMoney(value), Icons.inventory),
    ];
    if (items.isEmpty) return const Text('No hay indicadores disponibles.');
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 4 : 2,
        childAspectRatio: wide ? 1.8 : 1.35,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, index) {
        final item = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.$3),
                const SizedBox(height: 8),
                Text(item.$1),
                const SizedBox(height: 4),
                Text(item.$2, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.actions, required this.wide});
  final List<HomeAction> actions;
  final bool wide;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: actions.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: wide ? 5 : 2,
      childAspectRatio: wide ? 1.8 : 1.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemBuilder: (_, index) {
      final action = actions[index];
      return Card(
        child: InkWell(
          key: Key('home-action-${action.route}'),
          onTap: () => context.go(action.route),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon),
                const SizedBox(height: 8),
                Text(action.title, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    },
  );
}
