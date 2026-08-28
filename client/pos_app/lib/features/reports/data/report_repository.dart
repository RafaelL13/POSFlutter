import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/database/app_database.dart';

final class DashboardMetrics {
  const DashboardMetrics({
    required this.salesCents,
    required this.operations,
    this.fifoCostCents,
    this.grossProfitCents,
    this.expensesCents,
    this.marginBasisPoints,
  });

  final int salesCents;
  final int operations;
  final int? fifoCostCents;
  final int? grossProfitCents;
  final int? expensesCents;
  final int? marginBasisPoints;

  int? get resultCents {
    final profit = grossProfitCents;
    final expenses = expensesCents;
    return profit == null || expenses == null ? null : profit - expenses;
  }
}

final class ReportRepository {
  ReportRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<DashboardMetrics> today() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.saleHistory);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.saleHistory) ==
        PermissionLevel.ownOnly;
    final day = _clock().toUtc().toIso8601String().substring(0, 10);
    final database = await _db.open();
    final saleWhere =
        "branch_id = ? AND substr(sale_datetime, 1, 10) = ? AND status = 'Confirmed'${ownOnly ? ' AND user_id = ?' : ''}";
    final saleArgs = <Object?>[
      context.branchId,
      day,
      if (ownOnly) context.userId,
    ];
    final operational = await database.rawQuery(
      '''SELECT COALESCE(SUM(total_cents), 0) AS sales, COUNT(*) AS ops
         FROM sales WHERE $saleWhere''',
      saleArgs,
    );

    int? fifoCost;
    int? grossProfit;
    final canViewFifo = authorization.can(Capability.viewFifoHistoricalCost);
    final canViewProfit = authorization.can(Capability.viewProfit);
    final canViewMargin = authorization.can(Capability.viewMargin);
    if (canViewFifo || canViewProfit || canViewMargin) {
      final columns = <String>[];
      if (canViewFifo) columns.add('COALESCE(SUM(fifo_cost_cents), 0) AS cost');
      if (canViewProfit || canViewMargin) {
        columns.add('COALESCE(SUM(gross_profit_cents), 0) AS profit');
      }
      final sensitive = await database.rawQuery(
        'SELECT ${columns.join(', ')} FROM sales WHERE $saleWhere',
        saleArgs,
      );
      if (canViewFifo) fifoCost = sensitive.single['cost']! as int;
      if (canViewProfit) grossProfit = sensitive.single['profit']! as int;
    }

    int? expenses;
    if (authorization.can(Capability.expenseRead) &&
        authorization.can(Capability.viewExpenses)) {
      final rows = await database.rawQuery(
        '''SELECT COALESCE(SUM(amount_cents), 0) AS expenses FROM expenses
           WHERE branch_id = ? AND substr(expense_date, 1, 10) = ?''',
        [context.branchId, day],
      );
      expenses = rows.single['expenses']! as int;
    }

    final sales = operational.single['sales']! as int;
    int? margin;
    if (canViewMargin) {
      final rows = await database.rawQuery(
        '''SELECT COALESCE(SUM(gross_profit_cents), 0) AS profit
           FROM sales WHERE $saleWhere''',
        saleArgs,
      );
      final profit = rows.single['profit']! as int;
      margin = sales == 0 ? 0 : profit * 10000 ~/ sales;
    }

    return DashboardMetrics(
      salesCents: sales,
      operations: operational.single['ops']! as int,
      fifoCostCents: fifoCost,
      grossProfitCents: grossProfit,
      expensesCents: expenses,
      marginBasisPoints: margin,
    );
  }
}
