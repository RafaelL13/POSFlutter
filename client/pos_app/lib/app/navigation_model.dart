import 'package:flutter/material.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';

final class AppNavigationItem {
  const AppNavigationItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

final class AppNavigationSection {
  const AppNavigationSection({required this.title, required this.items});

  final String title;
  final List<AppNavigationItem> items;
}

const appNavigationSections = <AppNavigationSection>[
  AppNavigationSection(
    title: 'OPERACIÓN',
    items: [
      AppNavigationItem(
        label: 'Inicio',
        icon: Icons.home_outlined,
        route: '/dashboard',
      ),
      AppNavigationItem(
        label: 'Nueva venta',
        icon: Icons.point_of_sale,
        route: '/pos',
      ),
      AppNavigationItem(
        label: 'Ventas',
        icon: Icons.receipt_long,
        route: '/sales',
      ),
      AppNavigationItem(
        label: 'Caja',
        icon: Icons.account_balance_wallet_outlined,
        route: '/cash',
      ),
    ],
  ),
  AppNavigationSection(
    title: 'INVENTARIO',
    items: [
      AppNavigationItem(
        label: 'Productos',
        icon: Icons.inventory_2_outlined,
        route: '/products',
      ),
      AppNavigationItem(
        label: 'Categorías',
        icon: Icons.category_outlined,
        route: '/categories',
      ),
      AppNavigationItem(
        label: 'Proveedores',
        icon: Icons.local_shipping_outlined,
        route: '/suppliers',
      ),
      AppNavigationItem(
        label: 'Compras',
        icon: Icons.shopping_cart_outlined,
        route: '/purchases',
      ),
      AppNavigationItem(
        label: 'Inventario',
        icon: Icons.warehouse_outlined,
        route: '/inventory',
      ),
    ],
  ),
  AppNavigationSection(
    title: 'CONTROL',
    items: [
      AppNavigationItem(
        label: 'Gastos',
        icon: Icons.payments_outlined,
        route: '/expenses',
      ),
      AppNavigationItem(
        label: 'Reportes',
        icon: Icons.analytics_outlined,
        route: '/reports',
      ),
    ],
  ),
  AppNavigationSection(
    title: 'ADMINISTRACIÓN',
    items: [
      AppNavigationItem(
        label: 'Usuarios',
        icon: Icons.people_outline,
        route: '/users',
      ),
      AppNavigationItem(
        label: 'Respaldos',
        icon: Icons.backup_outlined,
        route: '/backup',
      ),
      AppNavigationItem(
        label: 'Administración nube',
        icon: Icons.cloud_outlined,
        route: '/cloud-admin',
      ),
    ],
  ),
];

List<AppNavigationSection> visibleNavigationSections(
  EffectiveCapabilities effective, {
  List<AppNavigationSection> sections = appNavigationSections,
}) {
  final visibleSections = <AppNavigationSection>[];
  for (final section in sections) {
    final visibleItems = section.items
        .where((item) => RouteAuthorization.canOpen(item.route, effective))
        .toList();
    if (visibleItems.isNotEmpty) {
      visibleSections.add(
        AppNavigationSection(title: section.title, items: visibleItems),
      );
    }
  }
  return visibleSections;
}
