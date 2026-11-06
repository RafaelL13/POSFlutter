import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/features/pos/data/web_combo_checkout_repository.dart';

final class _FakeApi implements JsonApiClient {
  String? lastPath;
  Map<String, Object?>? lastBody;
  @override
  Future<Map<String, Object?>> get(String path,
      {Map<String, String>? query, Map<String, String>? headers}) async => {};
  @override
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body,
      {bool authenticated = true}) async {
    lastPath = path;
    lastBody = body;
    return {
      'saleGlobalId': 'sale-1', 'folio': 'V-1', 'totalCents': 1500,
      'fifoCostCents': 900, 'alreadyProcessed': false,
      'saleDateTime': '2026-10-29T00:00:00Z',
    };
  }
}

void main() {
  test('envía combos versionados al checkout existente', () async {
    final api = _FakeApi();
    final repo = WebComboCheckoutRepository(api);
    final result = await repo.checkout(
      idempotencyKey: 'idem-1',
      combos: [const WebComboSelection(
        comboGlobalId: 'combo-1', expectedServerVersion: 3, quantity: 2)],
      payments: [const WebCheckoutPaymentSelection(method: 'Cash', amountCents: 1500)],
      receivedCashCents: 1500,
    );
    expect(api.lastPath, '/api/web/checkout');
    expect(api.lastBody!['idempotencyKey'], 'idem-1');
    final combos = api.lastBody!['combos'] as List;
    expect((combos.single as Map)['expectedServerVersion'], 3);
    expect(result.totalCents, 1500);
  });

  test('rechaza versión inválida sin enviar solicitud', () async {
    final api = _FakeApi();
    final repo = WebComboCheckoutRepository(api);
    await expectLater(
      repo.checkout(idempotencyKey: 'idem-2',
        combos: [const WebComboSelection(comboGlobalId: 'combo-1',
          expectedServerVersion: 0, quantity: 1)],
        payments: [const WebCheckoutPaymentSelection(method: 'Cash', amountCents: 100)]),
      throwsArgumentError,
    );
    expect(api.lastPath, isNull);
  });
}
