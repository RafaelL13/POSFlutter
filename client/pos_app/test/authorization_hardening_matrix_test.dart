import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/navigation_model.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/sync/sync_error.dart';
import 'package:pos_app/sync/sync_operation.dart';

void main() {
  const writeCapabilities = <Capability>[
    Capability.saleCreate,
    Capability.purchaseCreate,
    Capability.expenseCreate,
    Capability.productWrite,
    Capability.inventoryAdjust,
    Capability.backupRestore,
    Capability.syncPush,
  ];

  for (final role in AppRole.values) {
    test('AdminReadOnly blocks every critical write for ${role.name}', () {
      for (final capability in writeCapabilities) {
        expect(
          RolePolicy.effectivePermission(
            role: role,
            deviceMode: DeviceMode.adminReadOnly,
            capability: capability,
          ),
          PermissionLevel.none,
          reason: capability.name,
        );
      }
    });
  }

  for (final capability in <Capability>[
    Capability.saleCreate,
    Capability.usersRead,
    Capability.backupRestore,
    Capability.cloudAdminRead,
    Capability.syncPull,
  ]) {
    test('unknown role denies ${capability.name}', () {
      expect(
        RolePolicy.effectivePermission(
          role: AppRole.tryParse('UnknownRole'),
          deviceMode: DeviceMode.pointOfSale,
          capability: capability,
        ),
        PermissionLevel.none,
      );
    });

    test('unknown mode denies ${capability.name}', () {
      expect(
        RolePolicy.effectivePermission(
          role: AppRole.administrator,
          deviceMode: DeviceMode.tryParse('UnknownMode'),
          capability: capability,
        ),
        PermissionLevel.none,
      );
    });
  }

  for (final path in <String>[
    '/users',
    '/backup',
    '/cloud-admin',
    '/cloud-admin/reports/profit?period=today',
    '/purchases/foreign-id',
    '/expenses?branch=foreign',
    '/reports/../users',
  ]) {
    test('Seller direct route fails closed: $path', () {
      final effective = EffectiveCapabilities.fromContext(
        _context(role: 'Seller'),
      );
      expect(RouteAuthorization.canOpen(path, effective), isFalse);
      expect(
        RouteAuthorization.redirect(
          Uri.parse(path).path,
          RouteAccessState(
            configured: true,
            authenticated: true,
            capabilities: effective,
          ),
        ),
        '/dashboard',
      );
    });
  }

  for (final role in AppRole.values) {
    for (final mode in DeviceMode.values) {
      test(
        'visible navigation is authorized for ${role.name}/${mode.name}',
        () {
          final effective = EffectiveCapabilities.fromContext(
            _context(role: role.wireValue, deviceMode: mode.wireValue),
          );
          for (final section in visibleNavigationSections(effective)) {
            for (final item in section.items) {
              expect(
                RouteAuthorization.canOpen(item.route, effective),
                isTrue,
                reason: item.route,
              );
            }
          }
        },
      );
    }
  }

  test('unknown structured rejection never becomes retryable or synced', () {
    final failure = SyncFailure.fromOperationResult(
      const SyncOperationResult(
        'op-unknown',
        'Rejected',
        errorCode: 'TamperedAllowCode',
      ),
    );
    expect(failure.category, SyncErrorCategory.unsupportedOperation);
    expect(failure.disposition, SyncFailureDisposition.terminal);
    expect(failure.retryable, isFalse);
  });

  test('error text cannot override a terminal structured code', () {
    final failure = SyncFailure.fromOperationResult(
      const SyncOperationResult(
        'op-code-first',
        'Rejected',
        errorCode: 'RoleDenied',
        error: 'ServerError retry network temporary',
      ),
    );
    expect(failure.category, SyncErrorCategory.authorizationRejected);
    expect(failure.retryable, isFalse);
  });
}

LocalAppContext _context({
  String role = 'Administrator',
  String deviceMode = 'PointOfSale',
}) => LocalAppContext(
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
);
