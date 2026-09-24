import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/core/authorization/role_policy.dart';

void main() {
  group('Initial inventory authorization', () {
    test('Administrator can import initial inventory', () {
      expect(
        RolePolicy.permissionFor(
          AppRole.administrator,
          Capability.initialInventoryImport,
        ),
        PermissionLevel.full,
      );
    });

    test('Manager can import initial inventory', () {
      expect(
        RolePolicy.permissionFor(
          AppRole.manager,
          Capability.initialInventoryImport,
        ),
        PermissionLevel.full,
      );
    });

    test('Supervisor cannot import initial inventory', () {
      expect(
        RolePolicy.permissionFor(
          AppRole.supervisor,
          Capability.initialInventoryImport,
        ),
        PermissionLevel.none,
      );
    });

    test('Seller cannot import initial inventory', () {
      expect(
        RolePolicy.permissionFor(
          AppRole.seller,
          Capability.initialInventoryImport,
        ),
        PermissionLevel.none,
      );
    });

    test('AdminReadOnly blocks initial inventory import', () {
      expect(
        RolePolicy.effectivePermission(
          role: AppRole.administrator,
          deviceMode: DeviceMode.adminReadOnly,
          capability: Capability.initialInventoryImport,
        ),
        PermissionLevel.none,
      );

      expect(
        RolePolicy.effectivePermission(
          role: AppRole.manager,
          deviceMode: DeviceMode.adminReadOnly,
          capability: Capability.initialInventoryImport,
        ),
        PermissionLevel.none,
      );
    });

    test('PointOfSale preserves Administrator and Manager permission', () {
      expect(
        RolePolicy.effectivePermission(
          role: AppRole.administrator,
          deviceMode: DeviceMode.pointOfSale,
          capability: Capability.initialInventoryImport,
        ),
        PermissionLevel.full,
      );

      expect(
        RolePolicy.effectivePermission(
          role: AppRole.manager,
          deviceMode: DeviceMode.pointOfSale,
          capability: Capability.initialInventoryImport,
        ),
        PermissionLevel.full,
      );
    });
  });
}
