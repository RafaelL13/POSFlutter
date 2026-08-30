import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/dashboard/data/home_repository.dart';
import 'package:pos_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:pos_app/features/dashboard/presentation/home_content.dart';
import 'package:pos_app/features/reports/data/report_repository.dart';
import 'package:pos_app/sync/sync_health.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('all valid capability sets use the common authorized home', () {
    for (final role in ['Administrator', 'Manager', 'Supervisor', 'Seller']) {
      for (final mode in ['PointOfSale', 'AdminReadOnly']) {
        final capabilities = _capabilities(role, mode);
        expect(RouteAuthorization.authorizedHome(capabilities), '/dashboard');
        expect(RouteAuthorization.canOpen('/dashboard', capabilities), isTrue);
      }
    }
  });

  test('every visible home action is an authorized route', () {
    for (final role in ['Administrator', 'Manager', 'Supervisor', 'Seller']) {
      for (final mode in ['PointOfSale', 'AdminReadOnly']) {
        final capabilities = _capabilities(role, mode);
        for (final action in visibleHomeActions(capabilities)) {
          expect(
            RouteAuthorization.canOpen(action.route, capabilities),
            isTrue,
            reason: '$role/$mode/${action.route}',
          );
        }
      }
    }
  });

  testWidgets('Seller home focuses sales without sensitive or admin data', (
    tester,
  ) async {
    await _pump(tester, _summary('Seller'));

    expect(find.byKey(const Key('home-primary-sale')), findsOneWidget);
    expect(find.text('Ventas de hoy'), findsOneWidget);
    expect(find.text('Inventario disponible'), findsOneWidget);
    expect(find.text('Sin conexión — 2 cambios pendientes'), findsOneWidget);
    expect(find.text('Utilidad bruta'), findsNothing);
    expect(find.text('Margen'), findsNothing);
    expect(find.text('Gastos'), findsNothing);
    expect(find.text('Compras'), findsNothing);
    expect(find.text('Usuarios'), findsNothing);
  });

  testWidgets(
    'Supervisor home shows operations without financial/admin cards',
    (tester) async {
      await _pump(tester, _summary('Supervisor'));

      for (final label in [
        'Nueva venta',
        'Ventas',
        'Compras',
        'Inventario',
        'Gastos',
        'Reportes',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Utilidad bruta'), findsNothing);
      expect(find.text('Margen'), findsNothing);
      expect(find.text('Inventario valorizado'), findsNothing);
      expect(find.text('Usuarios'), findsNothing);
    },
  );

  testWidgets('Manager home presents permitted control and financial data', (
    tester,
  ) async {
    await _pump(tester, _summary('Manager', sensitive: true));

    for (final label in [
      'Utilidad bruta',
      'Margen',
      'Inventario valorizado',
      'Reportes',
      'Usuarios',
      'Administración nube',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Administrator home presents the complete authorized set', (
    tester,
  ) async {
    await _pump(tester, _summary('Administrator', sensitive: true));

    expect(find.byKey(const Key('home-primary-sale')), findsOneWidget);
    for (final label in [
      'Compras',
      'Gastos',
      'Usuarios',
      'Administración nube',
      'Respaldos',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('AdminReadOnly hides writes and keeps consultation routes', (
    tester,
  ) async {
    await _pump(
      tester,
      _summary('Administrator', mode: 'AdminReadOnly', sensitive: true),
    );

    expect(find.byKey(const Key('home-primary-sale')), findsNothing);
    expect(find.text('Dispositivo en modo consulta'), findsOneWidget);
    for (final label in [
      'Reportes',
      'Inventario',
      'Usuarios',
      'Administración nube',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  test('Seller home aggregate is OWN_ONLY and remains fully local', () async {
    final fixture = await _HomeFixture.create();
    addTearDown(fixture.dispose);

    final summary = await HomeRepository(fixture.database).load();

    expect(summary.metrics?.operations, 2);
    expect(summary.metrics?.salesCents, 200);
    expect(summary.metrics?.grossProfitCents, isNull);
    expect(summary.inventoryUnits, 7);
  });
}

Future<void> _pump(WidgetTester tester, HomeSummary summary) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(
        summary: summary,
        syncSummary: const SyncSummary(
          pendingCount: 2,
          retryingCount: 0,
          attentionCount: 0,
          conflictCount: 0,
          isOnline: false,
          isSyncing: false,
        ),
      ),
    ),
  );
  await tester.pump();
}

HomeSummary _summary(
  String role, {
  String mode = 'PointOfSale',
  bool sensitive = false,
}) => HomeSummary(
  capabilities: _capabilities(role, mode),
  userName: 'Rafael',
  branchName: 'Centro',
  deviceMode: mode,
  metrics: DashboardMetrics(
    salesCents: 120000,
    operations: 4,
    grossProfitCents: sensitive ? 30000 : null,
    expensesCents: sensitive ? 5000 : null,
    marginBasisPoints: sensitive ? 2500 : null,
  ),
  hasOpenCash: true,
  inventoryUnits: 42,
  inventoryValueCents: sensitive ? 800000 : null,
);

EffectiveCapabilities _capabilities(String role, String mode) =>
    EffectiveCapabilities.fromContext(
      LocalAppContext(
        businessId: 1,
        businessGlobalId: 'business-1',
        branchId: 2,
        branchGlobalId: 'branch-1',
        deviceId: 3,
        deviceGlobalId: 'device-1',
        deviceMode: mode,
        userId: 4,
        userGlobalId: 'user-1',
        role: role,
      ),
    );

final class _HomeFixture {
  _HomeFixture(this.database);
  final AppDatabase database;

  static Future<_HomeFixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final businessId = await db.insert('businesses', {
      'global_id': 'business-1',
      'name': 'Business',
      'created_at': now,
      'updated_at': now,
    });
    final branchId = await db.insert('branches', {
      'global_id': 'branch-1',
      'business_id': businessId,
      'name': 'Centro',
      'created_at': now,
      'updated_at': now,
    });
    final deviceId = await db.insert('devices', {
      'global_id': 'device-1',
      'branch_id': branchId,
      'name': 'POS',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });
    final sellerA = await db.insert('users', {
      'global_id': 'seller-a',
      'business_id': businessId,
      'name': 'Seller A',
      'username': 'seller-a',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': 'Seller',
      'created_at': now,
      'updated_at': now,
    });
    final sellerB = await db.insert('users', {
      'global_id': 'seller-b',
      'business_id': businessId,
      'name': 'Seller B',
      'username': 'seller-b',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': 'Seller',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'local_device_global_id',
      'value': 'device-1',
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'active_user_global_id',
      'value': 'seller-a',
      'updated_at': now,
    });
    final productId = await db.insert('products', {
      'global_id': 'product-1',
      'business_id': businessId,
      'code': 'P1',
      'name': 'Product',
      'presentation': 'Piece',
      'sale_price_cents': 100,
      'minimum_stock': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('inventory_lots', {
      'global_id': 'lot-1',
      'product_id': productId,
      'branch_id': branchId,
      'entry_date': now,
      'initial_quantity': 7,
      'available_quantity': 7,
      'unit_cost_cents': 10,
      'created_at': now,
    });
    for (var index = 0; index < 5; index++) {
      await db.insert('sales', {
        'global_id': 'sale-$index',
        'idempotency_key': 'idem-$index',
        'folio': 'V-$index',
        'sale_datetime': now,
        'user_id': index < 2 ? sellerA : sellerB,
        'device_id': deviceId,
        'branch_id': branchId,
        'subtotal_cents': 100,
        'discount_cents': 0,
        'total_cents': 100,
        'fifo_cost_cents': 10,
        'gross_profit_cents': 90,
        'payment_method': 'Cash',
        'change_cents': 0,
        'status': 'Confirmed',
        'created_at': now,
        'updated_at': now,
      });
    }
    return _HomeFixture(database);
  }

  Future<void> dispose() => database.close();
}
