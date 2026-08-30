import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';

const firstRunPath = '/first-run';
const loginPath = '/login';

final class RouteAccessState {
  const RouteAccessState({
    required this.configured,
    required this.authenticated,
    required this.capabilities,
  });

  final bool configured;
  final bool authenticated;
  final EffectiveCapabilities capabilities;
}

abstract final class RouteAuthorization {
  static const Map<String, Set<Capability>> protectedRoutes = {
    '/dashboard': {Capability.posAccess},
    '/pos': {Capability.saleCreate},
    '/products': {Capability.productRead},
    '/categories': {Capability.categoryRead},
    '/suppliers': {Capability.supplierRead},
    '/purchases': {Capability.purchaseRead},
    '/inventory': {Capability.inventoryAvailabilityRead},
    '/sales': {Capability.saleHistory},
    '/cash': {Capability.cashRead},
    '/expenses': {Capability.expenseRead},
    '/reports': {Capability.reportsOperational},
    '/users': {Capability.usersRead},
    '/backup': {Capability.backupCreate},
    '/cloud-admin': {Capability.cloudAdminRead},
    '/cloud-admin/reports': {
      Capability.cloudAdminRead,
      Capability.reportsFinancial,
    },
  };

  static Set<Capability>? requiredFor(String path) {
    if (path == '/cloud-admin/reports' ||
        path.startsWith('/cloud-admin/reports/')) {
      return protectedRoutes['/cloud-admin/reports'];
    }
    return protectedRoutes[path];
  }

  static bool canOpen(String path, EffectiveCapabilities effective) {
    final required = requiredFor(path);
    return required != null && required.every(effective.can);
  }

  static String authorizedHome(EffectiveCapabilities effective) {
    const candidates = <String>[
      '/dashboard',
      '/pos',
      '/cloud-admin',
      '/products',
      '/categories',
      '/inventory',
      '/sales',
      '/cash',
      '/purchases',
      '/expenses',
      '/suppliers',
      '/users',
      '/backup',
    ];
    for (final path in candidates) {
      if (canOpen(path, effective)) {
        return path;
      }
    }
    return loginPath;
  }

  static String? redirect(String path, RouteAccessState access) {
    if (!access.configured) {
      return path == firstRunPath ? null : firstRunPath;
    }

    if (!access.authenticated || !access.capabilities.hasValidContext) {
      return path == loginPath ? null : loginPath;
    }

    final home = authorizedHome(access.capabilities);
    if (path == firstRunPath || path == loginPath) {
      return home == path ? null : home;
    }

    final required = requiredFor(path);
    if (required == null) {
      return home == path ? loginPath : home;
    }
    if (required.every(access.capabilities.can)) {
      return null;
    }
    return home == path ? loginPath : home;
  }
}
