import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';

enum RemoteReportKind { sales, products, lowPerformance, categories, users, purchases, suppliers, inventory, expenses, cash, paymentMethods, cancellations, trends }

extension RemoteReportKindInfo on RemoteReportKind {
  String get title => switch (this) {
        RemoteReportKind.sales => 'Ventas',
        RemoteReportKind.products => 'Productos',
        RemoteReportKind.lowPerformance => 'Bajo rendimiento',
        RemoteReportKind.categories => 'Categorías',
        RemoteReportKind.users => 'Vendedores',
        RemoteReportKind.purchases => 'Compras',
        RemoteReportKind.suppliers => 'Proveedores',
        RemoteReportKind.inventory => 'Inventario',
        RemoteReportKind.expenses => 'Gastos',
        RemoteReportKind.cash => 'Caja',
        RemoteReportKind.paymentMethods => 'Formas de pago',
        RemoteReportKind.cancellations => 'Cancelaciones',
        RemoteReportKind.trends => 'Tendencias',
      };

  String get path => switch (this) {
        RemoteReportKind.sales => '/api/admin/reports/sales',
        RemoteReportKind.products => '/api/admin/reports/products',
        RemoteReportKind.lowPerformance => '/api/admin/reports/products/low-performance',
        RemoteReportKind.categories => '/api/admin/reports/categories',
        RemoteReportKind.users => '/api/admin/reports/users',
        RemoteReportKind.purchases => '/api/admin/reports/purchases',
        RemoteReportKind.suppliers => '/api/admin/reports/suppliers',
        RemoteReportKind.inventory => '/api/admin/reports/inventory',
        RemoteReportKind.expenses => '/api/admin/reports/expenses',
        RemoteReportKind.cash => '/api/admin/reports/cash',
        RemoteReportKind.paymentMethods => '/api/admin/reports/payment-methods',
        RemoteReportKind.cancellations => '/api/admin/reports/cancellations',
        RemoteReportKind.trends => '/api/admin/reports/trends/products',
      };
}

final class RemoteReportRepository {
  RemoteReportRepository(this._api);
  final JsonApiClient _api;

  Future<RemoteReportCatalogs> catalogs() async {
    Future<List<RemoteReportOption>> load(String path, {bool showCode = false}) async {
      final json = await _api.get(path);
      final raw = json['items'];
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((item) {
        final map = Map<String, Object?>.from(item);
        final id = map['globalId']?.toString() ?? '';
        final name = map['name']?.toString() ?? '';
        final code = map['code']?.toString() ?? '';
        return RemoteReportOption(globalId: id, label: showCode && code.isNotEmpty ? '$code · $name' : name);
      }).where((item) => item.globalId.isNotEmpty).toList();
    }

    return RemoteReportCatalogs(
      products: await load('/api/products', showCode: true),
      categories: await load('/api/categories'),
      suppliers: await load('/api/suppliers'),
      users: await load('/api/users'),
    );
  }

  Future<RemoteSummary> summary(RemoteReportFilter filter) async => RemoteSummary.fromJson(await _api.get('/api/admin/reports/summary', query: filter.query));

  Future<RemoteReportTable> table(
    RemoteReportKind kind,
    RemoteReportFilter filter, {
    String? groupBy,
    String? metric,
    String sortBy = 'revenue',
    bool descending = true,
    int top = 50,
    String? productGlobalId,
    String? categoryGlobalId,
    String? supplierGlobalId,
    String? userGlobalId,
  }) async {
    final query = <String, String>{...filter.query};
    void putIfPresent(String key, String? value) {
      if (value != null && value.isNotEmpty) query[key] = value;
    }
    switch (kind) {
      case RemoteReportKind.sales:
        query['groupBy'] = groupBy ?? 'day';
        break;
      case RemoteReportKind.products:
        query.addAll({'sortBy': sortBy, 'descending': '$descending', 'top': '$top'});
        break;
      case RemoteReportKind.lowPerformance:
        query.addAll({'metric': metric ?? 'revenue', 'top': '$top'});
        break;
      case RemoteReportKind.purchases:
        query['groupBy'] = groupBy ?? 'supplier';
        break;
      case RemoteReportKind.expenses:
        query.addAll({'groupBy': groupBy ?? 'category', 'page': '1', 'pageSize': '100'});
        break;
      case RemoteReportKind.cash || RemoteReportKind.cancellations:
        query.addAll({'page': '1', 'pageSize': '100'});
        break;
      case RemoteReportKind.trends:
        query['top'] = '$top';
        break;
      case RemoteReportKind.inventory || RemoteReportKind.categories || RemoteReportKind.users || RemoteReportKind.suppliers || RemoteReportKind.paymentMethods:
        break;
    }
    if (kind == RemoteReportKind.products || kind == RemoteReportKind.lowPerformance || kind == RemoteReportKind.inventory || kind == RemoteReportKind.trends) {
      putIfPresent('productGlobalId', productGlobalId);
      putIfPresent('categoryGlobalId', categoryGlobalId);
    }
    if (kind == RemoteReportKind.categories) putIfPresent('categoryGlobalId', categoryGlobalId);
    if (kind == RemoteReportKind.purchases || kind == RemoteReportKind.suppliers) putIfPresent('supplierGlobalId', supplierGlobalId);
    if (kind == RemoteReportKind.sales || kind == RemoteReportKind.users || kind == RemoteReportKind.expenses || kind == RemoteReportKind.cash || kind == RemoteReportKind.cancellations) {
      putIfPresent('userGlobalId', userGlobalId);
    }
    if (kind == RemoteReportKind.inventory) {
      query.remove('from');
      query.remove('to');
    }
    final json = await _api.get(kind.path, query: query);
    return _tableFrom(kind, json);
  }

  RemoteReportTable _tableFrom(RemoteReportKind kind, Map<String, Object?> json) {
    List<Map<String, Object?>> rowsFrom(Object? raw) => raw is List ? raw.whereType<Map>().map((x) => Map<String, Object?>.from(x)).toList() : const [];
    switch (kind) {
      case RemoteReportKind.sales:
        return RemoteReportTable(title: kind.title, columns: const ['period', 'salesCents', 'transactions', 'units', 'fifoCostCents', 'grossProfitCents', 'marginPercent'], rows: rowsFrom(json['items']));
      case RemoteReportKind.products:
      case RemoteReportKind.lowPerformance:
        return RemoteReportTable(title: kind.title, columns: const ['code', 'name', 'categoryName', 'units', 'revenueCents', 'fifoCostCents', 'grossProfitCents', 'marginPercent', 'transactions'], rows: rowsFrom(json['items']), note: kind == RemoteReportKind.lowPerformance ? json['definition']?.toString() : null);
      case RemoteReportKind.categories:
        return RemoteReportTable(title: kind.title, columns: const ['category', 'units', 'revenueCents', 'fifoCostCents', 'grossProfitCents', 'marginPercent', 'revenueSharePercent'], rows: rowsFrom(json['items']));
      case RemoteReportKind.users:
        return RemoteReportTable(title: kind.title, columns: const ['name', 'role', 'salesCount', 'units', 'revenueCents', 'averageTicketCents', 'cancelledSalesCount', 'cancelledSalesCents'], rows: rowsFrom(json['items']));
      case RemoteReportKind.purchases:
        return RemoteReportTable(title: kind.title, columns: const ['groupName', 'purchases', 'units', 'amountCents', 'averageUnitCostCents'], rows: rowsFrom(json['items']));
      case RemoteReportKind.suppliers:
        return RemoteReportTable(title: kind.title, columns: const ['name', 'purchases', 'units', 'amountCents', 'productsSupplied', 'lastPurchaseAt'], rows: rowsFrom(json['items']));
      case RemoteReportKind.inventory:
        return RemoteReportTable(title: kind.title, columns: const ['code', 'name', 'stock', 'minimumStock', 'activeLots', 'remainingFifoCostCents', 'averageUnitCostCents', 'lastEntryAt', 'lastSaleAt'], rows: rowsFrom(json['items']));
      case RemoteReportKind.expenses:
        return RemoteReportTable(title: kind.title, columns: const ['group', 'amountCents', 'expenses'], rows: rowsFrom(json['breakdown']), note: 'Total: ${json['totalCents'] ?? 0} centavos · ${json['expenses'] ?? 0} gastos');
      case RemoteReportKind.cash:
        return RemoteReportTable(title: kind.title, columns: const ['userName', 'openedAt', 'closedAt', 'status', 'openingBalanceCents', 'cashSalesCents', 'cashExpensesCents', 'calculatedExpectedCashCents', 'recordedExpectedCashCents', 'countedCashCents', 'differenceCents'], rows: rowsFrom(json['items']), note: 'La nube actual no sincroniza movimientos manuales de caja; el esperado calculado usa saldo inicial + ventas en efectivo - gastos en efectivo.');
      case RemoteReportKind.paymentMethods:
        return RemoteReportTable(title: kind.title, columns: const ['paymentMethod', 'transactions', 'amountCents', 'percentage'], rows: rowsFrom(json['items']));
      case RemoteReportKind.cancellations:
        final details = json['details'] is Map ? Map<String, Object?>.from(json['details'] as Map) : const <String, Object?>{};
        return RemoteReportTable(title: kind.title, columns: const ['folio', 'saleDateTime', 'cancelledAt', 'userName', 'reason', 'units', 'amountCents'], rows: rowsFrom(details['items']), note: 'Tasa: ${json['cancellationRatePercent'] ?? 0}% · ${json['cancelledSalesCount'] ?? 0} cancelaciones · ${json['cancelledUnits'] ?? 0} unidades');
      case RemoteReportKind.trends:
        final rows = rowsFrom(json['items']);
        for (final row in rows) {
          ProductTrend.fromJson(row);
        }
        return RemoteReportTable(title: kind.title, columns: const ['code', 'name', 'currentUnits', 'previousUnits', 'currentRevenueCents', 'previousRevenueCents', 'unitsChangePercent', 'revenueChangePercent', 'trend'], rows: rows, note: 'Stable = cambio de ingreso entre -5% y +5%. Comparación contra el periodo inmediatamente anterior de igual duración.');
    }
  }
}
