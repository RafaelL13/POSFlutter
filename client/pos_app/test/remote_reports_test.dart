import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_csv_service.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_repository.dart';

final class _FakeApi implements JsonApiClient {
  _FakeApi(this.response, {this.error});
  final Map<String, Object?> response;
  final Object? error;
  String? lastPath;
  Map<String, String>? lastQuery;
  int postCalls = 0;

  @override
  Future<Map<String, Object?>> get(String path, {Map<String, String>? query}) async {
    lastPath = path;
    lastQuery = query;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body, {bool authenticated = true}) async {
    postCalls++;
    throw StateError('Los reportes remotos no deben escribir.');
  }
}

void main() {
  test('RemoteSummary parsea dinero, cantidades y margen', () {
    final summary = RemoteSummary.fromJson({
      'grossSalesCents': 14345,
      'netSalesCents': 12345,
      'salesCount': 3,
      'unitsSold': 7,
      'averageTicketCents': 4115,
      'fifoCostCents': 5000,
      'grossProfitCents': 7345,
      'grossMarginPercent': 59.5,
      'expensesCents': 1000,
      'resultAfterExpensesCents': 6345,
      'cancelledSalesCount': 1,
      'cancelledSalesCents': 2000,
      'cancellationRatePercent': 25,
      'inventoryUnits': 20,
      'inventoryValueCents': 9000,
    });
    expect(summary.grossSalesCents, 14345);
    expect(summary.netSalesCents, 12345);
    expect(summary.salesCount, 3);
    expect(summary.grossMarginPercent, 59.5);
    expect(summary.inventoryValueCents, 9000);
  });

  test('filtros envían UTC y nunca BusinessId', () {
    final filter = RemoteReportFilter.custom(DateTime(2026, 8, 1), DateTime(2026, 8, 7));
    expect(filter.query.keys, containsAll(['from', 'to']));
    expect(filter.query.keys, isNot(contains('businessId')));
    expect(filter.toExclusiveUtc.difference(filter.fromUtc).inDays, 7);
  });

  test('repository summary usa endpoint admin y conserva query', () async {
    final api = _FakeApi({
      'grossSalesCents': 100,
      'netSalesCents': 100,
      'salesCount': 1,
      'unitsSold': 1,
      'averageTicketCents': 100,
      'fifoCostCents': 40,
      'grossProfitCents': 60,
      'grossMarginPercent': 60,
      'expensesCents': 0,
      'resultAfterExpensesCents': 60,
      'cancelledSalesCount': 0,
      'cancelledSalesCents': 0,
      'cancellationRatePercent': 0,
      'inventoryUnits': 2,
      'inventoryValueCents': 80,
    });
    final filter = RemoteReportFilter.forPreset(ReportPreset.today, now: DateTime(2026, 8, 26, 10));
    final result = await RemoteReportRepository(api).summary(filter);
    expect(result.netSalesCents, 100);
    expect(api.lastPath, '/api/admin/reports/summary');
    expect(api.lastQuery, filter.query);
    expect(api.postCalls, 0);
  });

  test('repository remoto propaga estado offline tipado', () async {
    final api = _FakeApi(const {}, error: const CloudApiException(CloudFailure.network, 'Sin conexión con el servidor.'));
    final filter = RemoteReportFilter.forPreset(ReportPreset.today, now: DateTime(2026, 8, 26));
    await expectLater(RemoteReportRepository(api).summary(filter), throwsA(isA<CloudApiException>().having((e) => e.failure, 'failure', CloudFailure.network)));
  });

  test('clasifica 401 403 404 429 y 500 sin stack de servidor', () {
    expect(classifyCloudStatus(401), CloudFailure.unauthorized);
    expect(classifyCloudStatus(403), CloudFailure.forbidden);
    expect(classifyCloudStatus(404), CloudFailure.notFound);
    expect(classifyCloudStatus(429), CloudFailure.rateLimited);
    expect(classifyCloudStatus(500), CloudFailure.server);
  });

  test('CSV remoto escapa comas y comillas', () {
    const table = RemoteReportTable(title: 'Ventas', columns: ['name', 'amountCents'], rows: [
      {'name': 'Producto, "A"', 'amountCents': 1234},
    ]);
    final csv = RemoteReportCsvService().buildCsv(table);
    expect(csv, contains('"Producto, ""A"""'));
    expect(csv, contains('"1234"'));
  });

  test('tendencia conserva clasificación explicable del servidor', () {
    final trend = ProductTrend.fromJson({'name': 'Melaza', 'currentRevenueCents': 5000, 'previousRevenueCents': 10000, 'revenueChangePercent': -50, 'trend': 'Declining'});
    expect(trend.name, 'Melaza');
    expect(trend.revenueChangePercent, -50);
    expect(trend.trend, 'Declining');
  });

  test('inventario remoto no manda periodo ni BusinessId', () async {
    final api = _FakeApi({'items': <Object?>[]});
    final filter = RemoteReportFilter.forPreset(ReportPreset.thisMonth, now: DateTime(2026, 8, 26));
    await RemoteReportRepository(api).table(RemoteReportKind.inventory, filter);
    expect(api.lastPath, '/api/admin/reports/inventory');
    expect(api.lastQuery, isNot(containsPair('from', anything)));
    expect(api.lastQuery, isNot(containsPair('to', anything)));
    expect(api.lastQuery, isNot(containsPair('businessId', anything)));
  });

  test('filtros dimensionales usan GlobalId y nunca BusinessId', () async {
    final api = _FakeApi({'items': <Object?>[]});
    final filter = RemoteReportFilter.forPreset(ReportPreset.last7Days, now: DateTime(2026, 8, 26));
    await RemoteReportRepository(api).table(
      RemoteReportKind.products,
      filter,
      productGlobalId: '11111111-1111-1111-1111-111111111111',
      categoryGlobalId: '22222222-2222-2222-2222-222222222222',
    );
    expect(api.lastQuery?['productGlobalId'], '11111111-1111-1111-1111-111111111111');
    expect(api.lastQuery?['categoryGlobalId'], '22222222-2222-2222-2222-222222222222');
    expect(api.lastQuery, isNot(containsPair('businessId', anything)));
  });

  test('repository de reportes es read-only para AdminReadOnly', () async {
    final api = _FakeApi({'items': <Object?>[]});
    final filter = RemoteReportFilter.forPreset(ReportPreset.last7Days, now: DateTime(2026, 8, 26));
    await RemoteReportRepository(api).table(RemoteReportKind.paymentMethods, filter);
    expect(api.postCalls, 0);
    expect(api.lastPath, '/api/admin/reports/payment-methods');
  });
}
