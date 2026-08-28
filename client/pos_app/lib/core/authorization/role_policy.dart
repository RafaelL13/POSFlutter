import 'app_role.dart';
import 'capability.dart';
import 'device_mode.dart';

const authorizationPolicyVersion = 1;

enum PermissionLevel { none, ownOnly, read, full, requiresAuthorization }

abstract final class RolePolicy {
  static PermissionLevel permissionFor(AppRole? role, Capability capability) {
    if (role == null) {
      return PermissionLevel.none;
    }

    return switch (role) {
      AppRole.administrator => _administrator(capability),
      AppRole.manager => _manager(capability),
      AppRole.supervisor => _supervisor(capability),
      AppRole.seller => _seller(capability),
    };
  }

  static PermissionLevel effectivePermission({
    required AppRole? role,
    required DeviceMode? deviceMode,
    required Capability capability,
  }) {
    if (role == null || deviceMode == null) {
      return PermissionLevel.none;
    }

    final basePermission = permissionFor(role, capability);

    if (basePermission == PermissionLevel.none) {
      return PermissionLevel.none;
    }

    if (deviceMode == DeviceMode.adminReadOnly &&
        capability.blockedByAdminReadOnly) {
      return PermissionLevel.none;
    }

    return basePermission;
  }

  static Set<Capability> capabilitiesFor(
    AppRole? role, {
    DeviceMode deviceMode = DeviceMode.pointOfSale,
  }) {
    if (role == null) {
      return const <Capability>{};
    }

    return {
      for (final capability in Capability.values)
        if (effectivePermission(
              role: role,
              deviceMode: deviceMode,
              capability: capability,
            ) !=
            PermissionLevel.none)
          capability,
    };
  }

  static PermissionLevel _administrator(Capability capability) {
    return switch (capability) {
      Capability.backupRestore => PermissionLevel.requiresAuthorization,
      _ => PermissionLevel.full,
    };
  }

  static PermissionLevel _manager(Capability capability) {
    return switch (capability) {
      Capability.usersWrite ||
      Capability.devicesWrite ||
      Capability.businessWrite ||
      Capability.branchesWrite ||
      Capability.enrollment ||
      Capability.backupRestore => PermissionLevel.none,

      Capability.usersRead ||
      Capability.devicesRead ||
      Capability.businessRead ||
      Capability.branchesRead ||
      Capability.reportsFinancial ||
      Capability.viewPurchaseCost ||
      Capability.viewFifoHistoricalCost ||
      Capability.viewProfit ||
      Capability.viewMargin ||
      Capability.viewSupplierPrice ||
      Capability.viewExpenses ||
      Capability.viewInventoryValue => PermissionLevel.read,

      _ => PermissionLevel.full,
    };
  }

  static PermissionLevel _supervisor(Capability capability) {
    return switch (capability) {
      Capability.posAccess ||
      Capability.saleCreate ||
      Capability.cashOpen ||
      Capability.cashClose ||
      Capability.purchaseCreate ||
      Capability.expenseCreate => PermissionLevel.full,

      Capability.saleHistory ||
      Capability.cashRead ||
      Capability.purchaseRead ||
      Capability.expenseRead ||
      Capability.productRead ||
      Capability.categoryRead ||
      Capability.inventoryAvailabilityRead ||
      Capability.inventoryLotsRead ||
      Capability.reportsOperational ||
      Capability.branchesRead ||
      Capability.viewExpenses => PermissionLevel.read,

      Capability.saleCancel ||
      Capability.saleDiscount ||
      Capability.cashCloseWithDifference ||
      Capability.cashWithdrawal ||
      Capability.productPriceChange ||
      Capability.inventoryAdjust => PermissionLevel.requiresAuthorization,

      Capability.syncPush || Capability.syncPull => PermissionLevel.full,

      _ => PermissionLevel.none,
    };
  }

  static PermissionLevel _seller(Capability capability) {
    return switch (capability) {
      Capability.posAccess ||
      Capability.saleCreate ||
      Capability.syncPush ||
      Capability.syncPull => PermissionLevel.full,

      Capability.saleHistory ||
      Capability.cashOpen ||
      Capability.cashRead ||
      Capability.cashClose => PermissionLevel.ownOnly,

      Capability.productRead ||
      Capability.categoryRead ||
      Capability.inventoryAvailabilityRead => PermissionLevel.read,

      Capability.saleCancel ||
      Capability.saleDiscount ||
      Capability.cashCloseWithDifference =>
        PermissionLevel.requiresAuthorization,

      _ => PermissionLevel.none,
    };
  }
}
