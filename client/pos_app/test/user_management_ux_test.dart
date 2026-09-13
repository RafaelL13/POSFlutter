import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/users/data/user_repository.dart';
import 'package:pos_app/features/users/presentation/users_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final users = <UserSummary>[
    const UserSummary(
      id: 1,
      globalId: 'hidden-admin-id',
      name: 'Ana Admin',
      username: 'ana',
      role: AppRole.administrator,
      active: true,
    ),
    const UserSummary(
      id: 2,
      globalId: 'hidden-seller-id',
      name: 'Sara Ventas',
      username: 'sara',
      role: AppRole.seller,
      active: true,
    ),
  ];

  testWidgets('Administrator sees tenant users and opens Agregar usuario', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: UsersScreen(loader: () async => (users, true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana Admin'), findsOneWidget);
    expect(find.text('Sara Ventas'), findsOneWidget);
    expect(find.byKey(const Key('add-user')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(find.text('Tipo de usuario *'), findsOneWidget);
    expect(find.textContaining('hidden-'), findsNothing);
  });

  testWidgets('role combobox contains exactly four fixed roles', (
    tester,
  ) async {
    await _openEditor(tester);
    await tester.tap(find.byKey(const Key('user-role-combobox')));
    await tester.pumpAndSettle();
    for (final label in [
      'Administrador',
      'Gerente',
      'Supervisor',
      'Vendedor',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('AdminReadOnly'), findsNothing);
  });

  testWidgets(
    'UI maps Gerente to Manager and password mismatch blocks submit',
    (tester) async {
      UserFormResult? result;
      await _openEditor(tester, onResult: (value) => result = value);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre completo *'),
        'Mario Pérez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Usuario *'),
        'MARIO.P',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña *'),
        'segura123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña *'),
        'diferente',
      );
      await tester.tap(find.byKey(const Key('user-role-combobox')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gerente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-user')));
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña *'),
        'segura123',
      );
      await tester.tap(find.byKey(const Key('save-user')));
      await tester.pumpAndSettle();
      expect(result?.input.role, AppRole.manager);
      expect(result?.input.username, 'mario.p');
    },
  );

  test('arbitrary roles and DeviceMode cannot become AppRole', () {
    expect(AppRole.tryParse('Owner'), isNull);
    expect(AppRole.tryParse('AdminReadOnly'), isNull);
    expect(AppRole.values, hasLength(4));
  });

  test(
    'Seller cannot enter users and Supervisor cannot elevate privileges',
    () async {
      final seller = EffectiveCapabilities.fromContext(_context('Seller'));
      expect(RouteAuthorization.canOpen('/users', seller), isFalse);
      final database = await _database('Supervisor');
      addTearDown(database.close);
      await expectLater(
        UserRepository(database).create(
          input: const UserInput(
            name: 'Elevated',
            username: 'elevated',
            role: AppRole.administrator,
            active: true,
          ),
          password: 'segura123',
        ),
        throwsA(isA<AuthorizationDeniedException>()),
      );
      final db = await database.open();
      final count = (await db.rawQuery('SELECT COUNT(*) count FROM users'))
          .single['count'];
      expect(count, 1);
    },
  );

  test(
    'Administrator lists tenant users and excludes foreign tenants',
    () async {
      final database = await _database('Administrator');
      addTearDown(database.close);
      final db = await database.open();
      final now = DateTime.utc(2026, 9, 12).toIso8601String();
      await db.insert('users', {
        'global_id': 'user-2',
        'business_id': 1,
        'name': 'Tenant Seller',
        'username': 'tenant.seller',
        'password_hash': 'hash',
        'password_salt': 'salt',
        'role': 'Seller',
        'created_at': now,
        'updated_at': now,
      });
      final foreignBusiness = await db.insert('businesses', {
        'global_id': 'business-2',
        'name': 'Foreign',
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('users', {
        'global_id': 'user-foreign',
        'business_id': foreignBusiness,
        'name': 'Foreign User',
        'username': 'foreign',
        'password_hash': 'hash',
        'password_salt': 'salt',
        'role': 'Administrator',
        'created_at': now,
        'updated_at': now,
      });
      final result = await UserRepository(database).list();
      expect(
        result.map((user) => user.name),
        containsAll(['Current', 'Tenant Seller']),
      );
      expect(result.map((user) => user.name), isNot(contains('Foreign User')));
    },
  );

  test(
    'Administrator creation is normalized and atomic with SyncQueue',
    () async {
      final database = await _database('Administrator');
      addTearDown(database.close);
      final repository = UserRepository(database);
      await repository.create(
        input: const UserInput(
          name: 'Mario Gerente',
          username: '  MARIO.G  ',
          role: AppRole.manager,
          active: true,
        ),
        password: 'segura123',
      );
      final db = await database.open();
      final created = (await db.query(
        'users',
        where: 'username=?',
        whereArgs: ['mario.g'],
      )).single;
      expect(created['role'], 'Manager');
      expect(
        await db.query(
          'sync_queue',
          where: "entity_type='User' AND entity_global_id=?",
          whereArgs: [created['global_id']],
        ),
        hasLength(1),
      );
      await expectLater(
        repository.create(
          input: const UserInput(
            name: 'Duplicado',
            username: 'MARIO.G',
            role: AppRole.seller,
            active: true,
          ),
          password: 'segura123',
        ),
        throwsA(anything),
      );
      expect(
        await db.query('users', where: 'username=?', whereArgs: ['mario.g']),
        hasLength(1),
      );
      expect(
        await db.query('sync_queue', where: "entity_type='User'"),
        hasLength(1),
      );
    },
  );

  testWidgets('user management is responsive and protects rapid double open', (
    tester,
  ) async {
    for (final size in [
      const Size(390, 844),
      const Size(800, 1280),
      const Size(1280, 800),
      const Size(1920, 1080),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: UsersScreen(loader: () async => (users, true))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-user')));
      await tester.tap(find.byKey(const Key('add-user')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(UserEditorDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('user editor emits one result on rapid double submit', (
    tester,
  ) async {
    var resultCount = 0;
    await _openEditor(
      tester,
      onResult: (result) {
        if (result != null) resultCount++;
      },
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre completo *'),
      'María López',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Usuario *'),
      'MARIA.LOPEZ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña *'),
      'segura123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña *'),
      'segura123',
    );
    await tester.tap(find.byKey(const Key('user-role-combobox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vendedor').last);
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('save-user'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(resultCount, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openEditor(
  WidgetTester tester, {
  ValueChanged<UserFormResult?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              final value = await showDialog<UserFormResult>(
                context: context,
                builder: (_) => const UserEditorDialog(),
              );
              onResult?.call(value);
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

LocalAppContext _context(String role) => LocalAppContext(
  businessId: 1,
  businessGlobalId: 'business-1',
  branchId: 1,
  branchGlobalId: 'branch-1',
  deviceId: 1,
  deviceGlobalId: 'device-1',
  deviceMode: 'PointOfSale',
  userId: 1,
  userGlobalId: 'user-1',
  role: role,
);

Future<AppDatabase> _database(String role) async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final db = await database.open();
  final now = DateTime.utc(2026, 9, 12).toIso8601String();
  final businessId = await db.insert('businesses', {
    'global_id': 'business-1',
    'name': 'Test',
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
  await db.insert('devices', {
    'global_id': 'device-1',
    'branch_id': branchId,
    'name': 'Tablet',
    'mode': 'PointOfSale',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('users', {
    'global_id': 'user-1',
    'business_id': businessId,
    'name': 'Current',
    'username': 'current',
    'password_hash': 'hash',
    'password_salt': 'salt',
    'role': role,
    'created_at': now,
    'updated_at': now,
  });
  for (final entry in {
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
