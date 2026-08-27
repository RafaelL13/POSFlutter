enum ReportPreset { today, yesterday, last7Days, thisMonth, previousMonth, custom }

final class RemoteReportFilter {
  const RemoteReportFilter({required this.fromUtc, required this.toExclusiveUtc, required this.preset});

  final DateTime fromUtc;
  final DateTime toExclusiveUtc;
  final ReportPreset preset;

  factory RemoteReportFilter.forPreset(ReportPreset preset, {DateTime? now}) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    return switch (preset) {
      ReportPreset.today => RemoteReportFilter(fromUtc: today.toUtc(), toExclusiveUtc: today.add(const Duration(days: 1)).toUtc(), preset: preset),
      ReportPreset.yesterday => RemoteReportFilter(fromUtc: today.subtract(const Duration(days: 1)).toUtc(), toExclusiveUtc: today.toUtc(), preset: preset),
      ReportPreset.last7Days => RemoteReportFilter(fromUtc: today.subtract(const Duration(days: 6)).toUtc(), toExclusiveUtc: today.add(const Duration(days: 1)).toUtc(), preset: preset),
      ReportPreset.thisMonth => RemoteReportFilter(fromUtc: DateTime(localNow.year, localNow.month).toUtc(), toExclusiveUtc: DateTime(localNow.year, localNow.month + 1).toUtc(), preset: preset),
      ReportPreset.previousMonth => RemoteReportFilter(fromUtc: DateTime(localNow.year, localNow.month - 1).toUtc(), toExclusiveUtc: DateTime(localNow.year, localNow.month).toUtc(), preset: preset),
      ReportPreset.custom => RemoteReportFilter(fromUtc: today.toUtc(), toExclusiveUtc: today.add(const Duration(days: 1)).toUtc(), preset: preset),
    };
  }

  factory RemoteReportFilter.custom(DateTime startLocal, DateTime endLocalInclusive) {
    final start = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final endExclusive = DateTime(endLocalInclusive.year, endLocalInclusive.month, endLocalInclusive.day).add(const Duration(days: 1));
    if (!endExclusive.isAfter(start)) throw ArgumentError('El periodo personalizado es inválido.');
    return RemoteReportFilter(fromUtc: start.toUtc(), toExclusiveUtc: endExclusive.toUtc(), preset: ReportPreset.custom);
  }

  Map<String, String> get query => {'from': fromUtc.toIso8601String(), 'to': toExclusiveUtc.toIso8601String()};

  String get label => switch (preset) {
        ReportPreset.today => 'Hoy',
        ReportPreset.yesterday => 'Ayer',
        ReportPreset.last7Days => 'Últimos 7 días',
        ReportPreset.thisMonth => 'Este mes',
        ReportPreset.previousMonth => 'Mes anterior',
        ReportPreset.custom => 'Personalizado',
      };
}

final class RemoteSummary {
  const RemoteSummary({
    required this.grossSalesCents,
    required this.netSalesCents,
    required this.salesCount,
    required this.unitsSold,
    required this.averageTicketCents,
    required this.fifoCostCents,
    required this.grossProfitCents,
    required this.grossMarginPercent,
    required this.expensesCents,
    required this.resultAfterExpensesCents,
    required this.cancelledSalesCount,
    required this.cancelledSalesCents,
    required this.cancellationRatePercent,
    required this.inventoryUnits,
    required this.inventoryValueCents,
  });

  final int grossSalesCents;
  final int netSalesCents;
  final int salesCount;
  final int unitsSold;
  final int averageTicketCents;
  final int fifoCostCents;
  final int grossProfitCents;
  final double grossMarginPercent;
  final int expensesCents;
  final int resultAfterExpensesCents;
  final int cancelledSalesCount;
  final int cancelledSalesCents;
  final double cancellationRatePercent;
  final int inventoryUnits;
  final int inventoryValueCents;

  factory RemoteSummary.fromJson(Map<String, Object?> json) => RemoteSummary(
        grossSalesCents: _int(json['grossSalesCents']),
        netSalesCents: _int(json['netSalesCents']),
        salesCount: _int(json['salesCount']),
        unitsSold: _int(json['unitsSold']),
        averageTicketCents: _int(json['averageTicketCents']),
        fifoCostCents: _int(json['fifoCostCents']),
        grossProfitCents: _int(json['grossProfitCents']),
        grossMarginPercent: _double(json['grossMarginPercent']),
        expensesCents: _int(json['expensesCents']),
        resultAfterExpensesCents: _int(json['resultAfterExpensesCents']),
        cancelledSalesCount: _int(json['cancelledSalesCount']),
        cancelledSalesCents: _int(json['cancelledSalesCents']),
        cancellationRatePercent: _double(json['cancellationRatePercent']),
        inventoryUnits: _int(json['inventoryUnits']),
        inventoryValueCents: _int(json['inventoryValueCents']),
      );
}

final class ProductTrend {
  const ProductTrend({required this.name, required this.currentRevenueCents, required this.previousRevenueCents, required this.revenueChangePercent, required this.trend});
  final String name;
  final int currentRevenueCents;
  final int previousRevenueCents;
  final double revenueChangePercent;
  final String trend;

  factory ProductTrend.fromJson(Map<String, Object?> json) => ProductTrend(
        name: json['name']?.toString() ?? '',
        currentRevenueCents: _int(json['currentRevenueCents']),
        previousRevenueCents: _int(json['previousRevenueCents']),
        revenueChangePercent: _double(json['revenueChangePercent']),
        trend: json['trend']?.toString() ?? 'Stable',
      );
}

final class RemoteReportTable {
  const RemoteReportTable({required this.title, required this.columns, required this.rows, this.note});
  final String title;
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final String? note;
}

int _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
double _double(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;


final class RemoteReportOption {
  const RemoteReportOption({required this.globalId, required this.label});
  final String globalId;
  final String label;
}

final class RemoteReportCatalogs {
  const RemoteReportCatalogs({required this.products, required this.categories, required this.suppliers, required this.users});
  final List<RemoteReportOption> products;
  final List<RemoteReportOption> categories;
  final List<RemoteReportOption> suppliers;
  final List<RemoteReportOption> users;
}
