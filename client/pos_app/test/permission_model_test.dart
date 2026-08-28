import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/core/authorization/role_policy.dart';

void main() {
  group('role parsing', () {
    test('valid roles parse to typed AppRole values', () {
      expect(AppRole.tryParse('Administrator'), AppRole.administrator);
      expect(AppRole.tryParse('Manager'), AppRole.manager);
      expect(AppRole.tryParse('Supervisor'), AppRole.supervisor);
      expect(AppRole.tryParse('Seller'), AppRole.seller);
    });

    test('unknown role fails closed', () {
      expect(AppRole.tryParse('Unknown'), isNull);
      expect(AppRole.tryParse(''), isNull);
      expect(AppRole.tryParse(null), isNull);

      expect(
        RolePolicy.permissionFor(
          AppRole.tryParse('Unknown'),
          Capability.saleCreate,
        ),
        PermissionLevel.none,
      );
    });
  });

  group('device mode parsing', () {
    test('valid device modes parse', () {
      expect(DeviceMode.tryParse('PointOfSale'), DeviceMode.pointOfSale);
      expect(DeviceMode.tryParse('AdminReadOnly'), DeviceMode.adminReadOnly);
    });

    test('unknown device mode fails closed', () {
      expect(DeviceMode.tryParse('Unknown'), isNull);

      expect(
        RolePolicy.effectivePermission(
          role: AppRole.administrator,
          deviceMode: DeviceMode.tryParse('Unknown'),
          capability: Capability.saleCreate,
        ),
        PermissionLevel.none,
      );
    });
  });

  group('Administrator policy', () {
    test('has administrative capabilities', () {
      for (final capability in <Capability>[
        Capability.saleCreate,
        Capability.purchaseCreate,
        Capability.expenseCreate,
        Capability.productWrite,
        Capability.categoryWrite,
        Capability.supplierWrite,
        Capability.inventoryAdjust,
        Capability.reportsFinancial,
        Capability.usersWrite,
        Capability.devicesWrite,
        Capability.businessWrite,
        Capability.branchesWrite,
        Capability.enrollment,
        Capability.backupCreate,
        Capability.cloudAdminRead,
        Capability.viewProfit,
        Capability.viewInventoryValue,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.administrator, capability),
          PermissionLevel.full,
          reason: capability.name,
        );
      }

      expect(
        RolePolicy.permissionFor(
          AppRole.administrator,
          Capability.backupRestore,
        ),
        PermissionLevel.requiresAuthorization,
      );
    });
  });

  group('Manager policy', () {
    test('can write operational catalog', () {
      for (final capability in <Capability>[
        Capability.productWrite,
        Capability.categoryWrite,
        Capability.supplierWrite,
        Capability.purchaseCreate,
        Capability.expenseCreate,
        Capability.inventoryAdjust,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.manager, capability),
          PermissionLevel.full,
          reason: capability.name,
        );
      }
    });

    test('cannot administer users or devices', () {
      expect(
        RolePolicy.permissionFor(AppRole.manager, Capability.usersWrite),
        PermissionLevel.none,
      );

      expect(
        RolePolicy.permissionFor(AppRole.manager, Capability.devicesWrite),
        PermissionLevel.none,
      );

      expect(
        RolePolicy.permissionFor(AppRole.manager, Capability.enrollment),
        PermissionLevel.none,
      );
    });

    test('can read financial information', () {
      for (final capability in <Capability>[
        Capability.reportsFinancial,
        Capability.viewPurchaseCost,
        Capability.viewFifoHistoricalCost,
        Capability.viewProfit,
        Capability.viewMargin,
        Capability.viewSupplierPrice,
        Capability.viewExpenses,
        Capability.viewInventoryValue,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.manager, capability),
          PermissionLevel.read,
          reason: capability.name,
        );
      }
    });
  });

  group('Supervisor policy', () {
    test('can create purchases and expenses', () {
      expect(
        RolePolicy.permissionFor(AppRole.supervisor, Capability.purchaseCreate),
        PermissionLevel.full,
      );

      expect(
        RolePolicy.permissionFor(AppRole.supervisor, Capability.expenseCreate),
        PermissionLevel.full,
      );
    });

    test('cannot write product or supplier', () {
      expect(
        RolePolicy.permissionFor(AppRole.supervisor, Capability.productWrite),
        PermissionLevel.none,
      );

      expect(
        RolePolicy.permissionFor(AppRole.supervisor, Capability.supplierWrite),
        PermissionLevel.none,
      );
    });

    test('critical operations require authorization', () {
      for (final capability in <Capability>[
        Capability.saleCancel,
        Capability.saleDiscount,
        Capability.inventoryAdjust,
        Capability.cashCloseWithDifference,
        Capability.cashWithdrawal,
        Capability.productPriceChange,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.supervisor, capability),
          PermissionLevel.requiresAuthorization,
          reason: capability.name,
        );
      }
    });

    test('cannot view sensitive financial data', () {
      for (final capability in <Capability>[
        Capability.reportsFinancial,
        Capability.viewPurchaseCost,
        Capability.viewFifoHistoricalCost,
        Capability.viewProfit,
        Capability.viewMargin,
        Capability.viewSupplierPrice,
        Capability.viewInventoryValue,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.supervisor, capability),
          PermissionLevel.none,
          reason: capability.name,
        );
      }
    });
  });

  group('Seller policy', () {
    test('can create sale', () {
      expect(
        RolePolicy.permissionFor(AppRole.seller, Capability.saleCreate),
        PermissionLevel.full,
      );
    });

    test('cash and sale history are own-only', () {
      for (final capability in <Capability>[
        Capability.saleHistory,
        Capability.cashOpen,
        Capability.cashRead,
        Capability.cashClose,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.seller, capability),
          PermissionLevel.ownOnly,
          reason: capability.name,
        );
      }
    });

    test('cannot perform administrative operations', () {
      for (final capability in <Capability>[
        Capability.purchaseCreate,
        Capability.expenseCreate,
        Capability.productWrite,
        Capability.categoryWrite,
        Capability.supplierWrite,
        Capability.inventoryAdjust,
        Capability.usersWrite,
        Capability.devicesWrite,
        Capability.businessWrite,
        Capability.branchesWrite,
        Capability.backupCreate,
        Capability.cloudAdminRead,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.seller, capability),
          PermissionLevel.none,
          reason: capability.name,
        );
      }
    });

    test('cannot view sensitive financial data', () {
      for (final capability in <Capability>[
        Capability.reportsFinancial,
        Capability.viewPurchaseCost,
        Capability.viewFifoHistoricalCost,
        Capability.viewProfit,
        Capability.viewMargin,
        Capability.viewSupplierPrice,
        Capability.viewExpenses,
        Capability.viewInventoryValue,
      ]) {
        expect(
          RolePolicy.permissionFor(AppRole.seller, capability),
          PermissionLevel.none,
          reason: capability.name,
        );
      }
    });
  });

  group('device-mode filtering', () {
    test('AdminReadOnly blocks operational writes for Administrator', () {
      for (final capability in Capability.values.where(
        (capability) => capability.blockedByAdminReadOnly,
      )) {
        expect(
          RolePolicy.effectivePermission(
            role: AppRole.administrator,
            deviceMode: DeviceMode.adminReadOnly,
            capability: capability,
          ),
          PermissionLevel.none,
          reason: capability.name,
        );
      }
    });

    test('AdminReadOnly preserves allowed reads', () {
      expect(
        RolePolicy.effectivePermission(
          role: AppRole.administrator,
          deviceMode: DeviceMode.adminReadOnly,
          capability: Capability.productRead,
        ),
        PermissionLevel.full,
      );

      expect(
        RolePolicy.effectivePermission(
          role: AppRole.manager,
          deviceMode: DeviceMode.adminReadOnly,
          capability: Capability.viewProfit,
        ),
        PermissionLevel.read,
      );
    });

    test('device mode never increases role privileges', () {
      for (final role in AppRole.values) {
        for (final capability in Capability.values) {
          final base = RolePolicy.permissionFor(role, capability);

          final effective = RolePolicy.effectivePermission(
            role: role,
            deviceMode: DeviceMode.adminReadOnly,
            capability: capability,
          );

          if (base == PermissionLevel.none) {
            expect(
              effective,
              PermissionLevel.none,
              reason: '${role.name}/${capability.name}',
            );
          }
        }
      }
    });
  });

  group('matrix completeness', () {
    test('every role and capability has an explicit result', () {
      for (final role in AppRole.values) {
        for (final capability in Capability.values) {
          final permission = RolePolicy.permissionFor(role, capability);

          expect(
            PermissionLevel.values,
            contains(permission),
            reason: '${role.name}/${capability.name}',
          );
        }
      }
    });

    test('effective matrix is defined for both device modes', () {
      for (final role in AppRole.values) {
        for (final mode in DeviceMode.values) {
          for (final capability in Capability.values) {
            final permission = RolePolicy.effectivePermission(
              role: role,
              deviceMode: mode,
              capability: capability,
            );

            expect(
              PermissionLevel.values,
              contains(permission),
              reason: '${role.name}/${mode.name}/${capability.name}',
            );
          }
        }
      }
    });
  });

  test('authorization policy version is defined', () {
    expect(authorizationPolicyVersion, 1);
  });
}
