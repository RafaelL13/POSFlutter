import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/app/router.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/context/local_app_context.dart';

void main() {
  group('RouteAuthorization', () {
    test('first-run and login flows do not redirect in circles', () {
      expect(RouteAuthorization.redirect('/first-run', _notConfigured), isNull);
      expect(
        RouteAuthorization.redirect('/login', _notConfigured),
        '/first-run',
      );
      expect(RouteAuthorization.redirect('/login', _loggedOut), isNull);
      expect(RouteAuthorization.redirect('/first-run', _loggedOut), '/login');
    });

    test('not logged-in and invalid contexts fail closed', () {
      expect(RouteAuthorization.redirect('/pos', _loggedOut), '/login');
      expect(
        RouteAuthorization.redirect('/pos', _access(role: 'Unknown')),
        '/login',
      );
      expect(
        RouteAuthorization.redirect('/pos', _access(deviceMode: 'Unknown')),
        '/login',
      );
    });

    test('an unclassified route fails closed to the authorized home', () {
      final access = _access(role: 'Seller');
      expect(
        RouteAuthorization.redirect('/unclassified', access),
        '/dashboard',
      );
    });

    test(
      'Seller receives capability home and cannot open privileged routes',
      () {
        final access = _access(role: 'Seller');
        expect(
          RouteAuthorization.authorizedHome(access.capabilities),
          '/dashboard',
        );
        for (final path in [
          '/dashboard',
          '/pos',
          '/products',
          '/categories',
          '/inventory',
          '/sales',
          '/cash',
        ]) {
          expect(RouteAuthorization.redirect(path, access), isNull);
        }
        for (final path in [
          '/suppliers',
          '/purchases',
          '/expenses',
          '/reports',
          '/users',
          '/backup',
          '/cloud-admin',
        ]) {
          expect(RouteAuthorization.redirect(path, access), '/dashboard');
        }
      },
    );

    test('Supervisor can use operational routes but not privileged routes', () {
      final access = _access(role: 'Supervisor');
      expect(
        RouteAuthorization.authorizedHome(access.capabilities),
        '/dashboard',
      );
      expect(RouteAuthorization.redirect('/reports', access), isNull);
      expect(RouteAuthorization.redirect('/purchases', access), isNull);
      for (final path in ['/users', '/backup', '/cloud-admin']) {
        expect(RouteAuthorization.redirect(path, access), '/dashboard');
      }
    });

    test('Manager and Administrator can use their capability routes', () {
      for (final role in ['Manager', 'Administrator']) {
        final access = _access(role: role);
        for (final path in [
          '/pos',
          '/products',
          '/categories',
          '/suppliers',
          '/purchases',
          '/inventory',
          '/sales',
          '/cash',
          '/expenses',
          '/reports',
          '/users',
          '/backup',
          '/cloud-admin',
        ]) {
          expect(RouteAuthorization.redirect(path, access), isNull);
        }
        expect(
          RouteAuthorization.redirect('/cloud-admin/reports/sales', access),
          isNull,
        );
      }
    });

    test('AdminReadOnly cannot enter POS but retains authorized reads', () {
      final access = _access(deviceMode: 'AdminReadOnly');
      expect(RouteAuthorization.redirect('/pos', access), '/dashboard');
      expect(RouteAuthorization.redirect('/products', access), isNull);
      expect(RouteAuthorization.redirect('/users', access), isNull);
      expect(RouteAuthorization.redirect('/cloud-admin', access), isNull);
      expect(
        RouteAuthorization.redirect('/cloud-admin/reports/profit', access),
        isNull,
      );
    });

    test('authorized home is itself authorized for all supported contexts', () {
      for (final role in ['Seller', 'Supervisor', 'Manager', 'Administrator']) {
        for (final deviceMode in ['PointOfSale', 'AdminReadOnly']) {
          final access = _access(role: role, deviceMode: deviceMode);
          final home = RouteAuthorization.authorizedHome(access.capabilities);
          expect(home, isNot('/login'));
          expect(RouteAuthorization.redirect(home, access), isNull);
        }
      }
    });

    test('all protected paths have explicit capability requirements', () {
      expect(
        RouteAuthorization.protectedRoutes.keys,
        containsAll(<String>[
          '/dashboard',
          '/pos',
          '/products',
          '/categories',
          '/suppliers',
          '/purchases',
          '/inventory',
          '/sales',
          '/cash',
          '/expenses',
          '/reports',
          '/users',
          '/backup',
          '/cloud-admin',
          '/cloud-admin/reports',
        ]),
      );
    });
  });

  testWidgets('router.go enforces direct and nested navigation', (
    tester,
  ) async {
    var access = _access(role: 'Seller');
    final router = createAppRouter(
      initialLocation: '/pos',
      loadAccessState: () async => access,
      routes: _testRoutes,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('/pos'), findsOneWidget);

    router.go('/users');
    await tester.pumpAndSettle();
    expect(find.text('/dashboard'), findsOneWidget);

    access = _access(role: 'Administrator');
    router.go('/cloud-admin/reports/profit');
    await tester.pumpAndSettle();
    expect(find.text('/cloud-admin/reports/profit'), findsOneWidget);

    access = _access(deviceMode: 'AdminReadOnly');
    router.go('/pos');
    await tester.pumpAndSettle();
    expect(find.text('/dashboard'), findsOneWidget);
  });
}

final _notConfigured = RouteAccessState(
  configured: false,
  authenticated: false,
  capabilities: const EffectiveCapabilities.denied(),
);

final _loggedOut = RouteAccessState(
  configured: true,
  authenticated: false,
  capabilities: const EffectiveCapabilities.denied(),
);

RouteAccessState _access({
  String role = 'Administrator',
  String deviceMode = 'PointOfSale',
}) => RouteAccessState(
  configured: true,
  authenticated: true,
  capabilities: EffectiveCapabilities.fromContext(
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
  ),
);

final _testRoutes = <RouteBase>[
  for (final path in <String>{
    '/first-run',
    '/login',
    ...RouteAuthorization.protectedRoutes.keys,
  })
    GoRoute(path: path, builder: (_, state) => Text(state.uri.path)),
  GoRoute(
    path: '/cloud-admin/reports/:kind',
    builder: (_, state) => Text(state.uri.path),
  ),
];
