import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/navigation_model.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/features/cloud_admin/presentation/cloud_admin_screen.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';

void main() {
  group('capability-driven navigation model', () {
    test('every item reuses a protected route authorization rule', () {
      for (final section in appNavigationSections) {
        for (final item in section.items) {
          expect(RouteAuthorization.requiredFor(item.route), isNotNull);
        }
      }
    });

    test('Seller sees selling navigation and no privileged items', () {
      final labels = _labels(_effective(role: 'Seller'));
      expect(
        labels,
        containsAll([
          'Nueva venta',
          'Ventas',
          'Caja',
          'Productos',
          'Categorías',
          'Inventario',
        ]),
      );
      for (final hidden in [
        'Compras',
        'Gastos',
        'Proveedores',
        'Reportes',
        'Usuarios',
        'Respaldos',
        'Administración nube',
      ]) {
        expect(labels, isNot(contains(hidden)));
      }
    });

    test('Supervisor sees operations and no denied administration', () {
      final labels = _labels(_effective(role: 'Supervisor'));
      expect(
        labels,
        containsAll([
          'Nueva venta',
          'Ventas',
          'Caja',
          'Productos',
          'Categorías',
          'Compras',
          'Inventario',
          'Gastos',
          'Reportes',
        ]),
      );
      for (final hidden in ['Usuarios', 'Respaldos', 'Administración nube']) {
        expect(labels, isNot(contains(hidden)));
      }
    });

    test('Manager sees catalog, control and permitted administration', () {
      final labels = _labels(_effective(role: 'Manager'));
      expect(
        labels,
        containsAll([
          'Nueva venta',
          'Ventas',
          'Caja',
          'Productos',
          'Categorías',
          'Proveedores',
          'Compras',
          'Inventario',
          'Gastos',
          'Reportes',
          'Usuarios',
          'Respaldos',
          'Administración nube',
        ]),
      );
    });

    test('Administrator sees every relevant PointOfSale item', () {
      final sections = visibleNavigationSections(
        _effective(role: 'Administrator'),
      );
      expect(
        sections.expand((section) => section.items).length,
        appNavigationSections.expand((section) => section.items).length,
      );
    });

    test('AdminReadOnly hides sale entrypoint and keeps allowed reads', () {
      final labels = _labels(
        _effective(role: 'Administrator', deviceMode: 'AdminReadOnly'),
      );
      expect(labels, isNot(contains('Nueva venta')));
      expect(
        labels,
        containsAll([
          'Productos',
          'Inventario',
          'Reportes',
          'Usuarios',
          'Administración nube',
        ]),
      );
    });

    test('unknown role and device mode fail closed', () {
      expect(_labels(_effective(role: 'Unknown')), isEmpty);
      expect(_labels(_effective(deviceMode: 'Unknown')), isEmpty);
    });

    test('empty sections are hidden and non-empty sections remain', () {
      const sections = [
        AppNavigationSection(
          title: 'DENIED',
          items: [
            AppNavigationItem(
              label: 'Usuarios',
              icon: Icons.people,
              route: '/users',
            ),
          ],
        ),
        AppNavigationSection(
          title: 'ALLOWED',
          items: [
            AppNavigationItem(
              label: 'Nueva venta',
              icon: Icons.point_of_sale,
              route: '/pos',
            ),
          ],
        ),
      ];
      final visible = visibleNavigationSections(
        _effective(role: 'Seller'),
        sections: sections,
      );
      expect(visible.map((section) => section.title), ['ALLOWED']);
    });
  });

  testWidgets('real drawer hides Seller unauthorized items', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppNavigationDrawer(
          capabilities: _effective(role: 'Seller'),
          currentRoute: '/pos',
        ),
      ),
    );

    expect(find.text('Nueva venta'), findsOneWidget);
    expect(find.text('Productos'), findsOneWidget);
    expect(find.text('Compras'), findsNothing);
    expect(find.text('Usuarios'), findsNothing);
    expect(find.text('Administración nube'), findsNothing);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Nueva venta'))
          .selected,
      isTrue,
    );
  });

  testWidgets('real drawer reflects AdminReadOnly reduction', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppNavigationDrawer(
          capabilities: _effective(
            role: 'Administrator',
            deviceMode: 'AdminReadOnly',
          ),
          currentRoute: '/products',
        ),
      ),
    );

    expect(find.text('Nueva venta'), findsNothing);
    expect(find.text('Productos'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Inventario'), 250);
    expect(find.text('Inventario'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Reportes'), 250);
    expect(find.text('Reportes'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Administración nube'), 250);
    expect(find.text('Administración nube'), findsOneWidget);
  });

  testWidgets('Cloud Admin secondary navigation is capability filtered', (
    tester,
  ) async {
    final effective = _effective(role: 'Manager');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveCapabilitiesProvider.overrideWith((ref) async => effective),
        ],
        child: const MaterialApp(home: CloudAdminScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Reportes remotos'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dispositivos'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.byTooltip('Invitar dispositivo administrativo'), findsNothing);
  });
}

List<String> _labels(EffectiveCapabilities effective) =>
    visibleNavigationSections(effective)
        .expand((section) => section.items)
        .map((item) => item.label)
        .toList();

EffectiveCapabilities _effective({
  String role = 'Administrator',
  String deviceMode = 'PointOfSale',
}) => EffectiveCapabilities.fromContext(
  LocalAppContext(
    businessId: 1,
    businessGlobalId: 'business-1',
    branchId: 2,
    branchGlobalId: 'branch-1',
    deviceId: 3,
    deviceGlobalId: 'device-1',
    deviceMode: deviceMode,
    userId: 4,
    userGlobalId: 'user-1',
    role: role,
  ),
);
