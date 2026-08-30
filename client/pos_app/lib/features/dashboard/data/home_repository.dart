import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/cash/data/cash_read_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/features/reports/data/report_repository.dart';

final class HomeSummary {
  const HomeSummary({
    required this.capabilities,
    required this.userName,
    required this.branchName,
    required this.deviceMode,
    this.metrics,
    this.hasOpenCash,
    this.inventoryUnits,
    this.inventoryValueCents,
  });

  final EffectiveCapabilities capabilities;
  final String userName;
  final String branchName;
  final String deviceMode;
  final DashboardMetrics? metrics;
  final bool? hasOpenCash;
  final int? inventoryUnits;
  final int? inventoryValueCents;
}

final class HomeRepository {
  HomeRepository(this._database);

  final AppDatabase _database;

  Future<HomeSummary> load() async {
    final capabilities = await AuthorizationService(_database).load();
    if (!capabilities.hasValidContext) {
      throw StateError('No hay un contexto local autorizado.');
    }
    final context = capabilities.context!;
    final database = await _database.open();
    final identity = await database.rawQuery(
      '''SELECT u.name AS user_name, b.name AS branch_name
         FROM users u, branches b
         WHERE u.id = ? AND b.id = ? AND u.active = 1 AND b.active = 1''',
      [context.userId, context.branchId],
    );
    if (identity.isEmpty) {
      throw StateError('El contexto local ya no está activo.');
    }

    DashboardMetrics? metrics;
    if (capabilities.can(Capability.saleHistory)) {
      metrics = await _optional(() => ReportRepository(_database).today());
    }
    bool? hasOpenCash;
    if (capabilities.can(Capability.cashRead)) {
      hasOpenCash = await _optional(
        () => CashReadRepository(_database).hasOpenSession(),
      );
    }
    int? inventoryUnits;
    if (capabilities.can(Capability.inventoryAvailabilityRead)) {
      inventoryUnits = await _optional(
        () => InventoryReadRepository(_database).totalAvailableUnits(),
      );
    }
    int? inventoryValue;
    if (capabilities.can(Capability.viewInventoryValue)) {
      inventoryValue = await _optional(
        () => InventoryReadRepository(_database).inventoryValueCents(),
      );
    }

    return HomeSummary(
      capabilities: capabilities,
      userName: identity.single['user_name']! as String,
      branchName: identity.single['branch_name']! as String,
      deviceMode: context.deviceMode,
      metrics: metrics,
      hasOpenCash: hasOpenCash,
      inventoryUnits: inventoryUnits,
      inventoryValueCents: inventoryValue,
    );
  }

  Future<T?> _optional<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on Object {
      return null;
    }
  }
}
