import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/auth/data/auth_repository.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'logout invalidates session, clears tokens and preserves local data',
    () async {
      final database = await _seededDatabase();
      addTearDown(database.close);
      var tokenClearCount = 0;

      await AuthRepository(
        database,
        clearTokens: () async => tokenClearCount++,
      ).logout();

      final db = await database.open();
      expect(await _setting(db, 'local_session_authenticated'), '0');
      expect(await _setting(db, 'active_user_global_id'), isNull);
      expect(tokenClearCount, 1);
      for (final table in [
        'businesses',
        'branches',
        'devices',
        'users',
        'products',
        'inventory_lots',
        'sales',
        'sync_queue',
      ]) {
        expect(await _count(db, table), 1, reason: '$table must be preserved');
      }
      expect(await _setting(db, 'local_device_global_id'), 'device-1');
      expect(await _setting(db, 'configured'), '1');
    },
  );

  test('valid relogin works after logout', () async {
    final database = await _seededDatabase();
    addTearDown(database.close);
    final repository = AuthRepository(database, clearTokens: () async {});

    await repository.logout();
    final session = await repository.login('admin', 'password123');

    expect(session, isNotNull);
    final db = await database.open();
    expect(await _setting(db, 'local_session_authenticated'), '1');
    expect(await _setting(db, 'active_user_global_id'), 'user-1');
  });

  testWidgets('cancelling confirmation does not logout', (tester) async {
    var logoutCount = 0;
    final router = _router(onLogout: () async => logoutCount++);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await _revealLogout(tester);
    await tester.tap(find.byKey(const Key('logout-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(logoutCount, 0);
    expect(find.text('Protegida'), findsWidgets);
  });

  testWidgets('confirmation logs out once, goes to login and blocks back', (
    tester,
  ) async {
    var logoutCount = 0;
    final router = _router(
      onLogout: () async {
        logoutCount++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await _revealLogout(tester);
    await tester.tap(find.byKey(const Key('logout-tile')));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Cerrar sesión');
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(logoutCount, 1);
    expect(find.text('Login'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Protegida'), findsNothing);
  });
}

Future<void> _revealLogout(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('logout-tile')),
    300,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
}

GoRouter _router({required Future<void> Function() onLogout}) => GoRouter(
  initialLocation: '/protected',
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, _) => const Scaffold(body: Text('Login')),
    ),
    GoRoute(
      path: '/protected',
      builder: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Protegida')),
        drawer: AppNavigationDrawer(
          capabilities: EffectiveCapabilities.fromContext(_context()),
          currentRoute: '/protected',
          onLogout: onLogout,
        ),
        body: const Text('Protegida'),
      ),
    ),
  ],
);

LocalAppContext _context() => const LocalAppContext(
  businessId: 1,
  businessGlobalId: 'business-1',
  branchId: 1,
  branchGlobalId: 'branch-1',
  deviceId: 1,
  deviceGlobalId: 'device-1',
  deviceMode: 'PointOfSale',
  userId: 1,
  userGlobalId: 'user-1',
  role: 'Administrator',
);

Future<AppDatabase> _seededDatabase() async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final db = await database.open();
  final now = DateTime.utc(2026, 9, 12).toIso8601String();
  final password = await PasswordHasher().hash('password123');
  final businessId = await db.insert('businesses', {
    'global_id': 'business-1',
    'name': 'Negocio',
    'created_at': now,
    'updated_at': now,
  });
  final branchId = await db.insert('branches', {
    'global_id': 'branch-1',
    'business_id': businessId,
    'name': 'Principal',
    'created_at': now,
    'updated_at': now,
  });
  final deviceId = await db.insert('devices', {
    'global_id': 'device-1',
    'branch_id': branchId,
    'name': 'Tablet',
    'mode': 'PointOfSale',
    'created_at': now,
    'updated_at': now,
  });
  final userId = await db.insert('users', {
    'global_id': 'user-1',
    'business_id': businessId,
    'name': 'Administrador',
    'username': 'admin',
    'password_hash': password.hash,
    'password_salt': password.salt,
    'role': 'Administrator',
    'created_at': now,
    'updated_at': now,
  });
  final productId = await db.insert('products', {
    'global_id': 'product-1',
    'business_id': businessId,
    'code': 'P1',
    'name': 'Producto',
    'presentation': 'Piece',
    'sale_price_cents': 1000,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('inventory_lots', {
    'global_id': 'lot-1',
    'product_id': productId,
    'branch_id': branchId,
    'entry_date': now,
    'initial_quantity': 5,
    'available_quantity': 5,
    'unit_cost_cents': 500,
    'created_at': now,
  });
  await db.insert('sales', {
    'global_id': 'sale-1',
    'idempotency_key': 'sale-idempotency-1',
    'folio': 'V-1',
    'sale_datetime': now,
    'user_id': userId,
    'device_id': deviceId,
    'branch_id': branchId,
    'subtotal_cents': 1000,
    'discount_cents': 0,
    'total_cents': 1000,
    'fifo_cost_cents': 500,
    'gross_profit_cents': 500,
    'payment_method': 'Cash',
    'received_cents': 1000,
    'change_cents': 0,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('sync_queue', {
    'global_id': 'sync-1',
    'entity_type': 'Sale',
    'entity_global_id': 'sale-1',
    'operation': 'Create',
    'payload_json': '{}',
    'created_at': now,
  });
  for (final entry in {
    'configured': '1',
    'local_device_global_id': 'device-1',
    'active_user_global_id': 'user-1',
    'local_session_authenticated': '1',
  }.entries) {
    await db.insert('app_settings', {
      'key': entry.key,
      'value': entry.value,
      'updated_at': now,
    });
  }
  return database;
}

Future<String?> _setting(Database db, String key) async {
  final rows = await db.query(
    'app_settings',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['value'] as String;
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count'] as int;
}
