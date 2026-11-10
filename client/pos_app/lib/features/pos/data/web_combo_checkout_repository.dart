import 'package:pos_app/core/network/cloud_api_client.dart';

/// Contrato remoto: los precios y el inventario se calculan en SQL Server.
/// No sustituye el flujo local/offline de PosRepository.
final class WebComboSelection {
  const WebComboSelection({
    required this.comboGlobalId,
    required this.expectedServerVersion,
    required this.quantity,
  });
  final String comboGlobalId;
  final int expectedServerVersion;
  final int quantity;

  Map<String, Object?> toJson() {
    if (comboGlobalId.isEmpty ||
        expectedServerVersion < 1 || quantity < 1 || quantity > 1000) {
      throw ArgumentError('Selección de combo inválida.');
    }
    return {
      'comboGlobalId': comboGlobalId,
      'expectedServerVersion': expectedServerVersion,
      'quantity': quantity,
    };
  }
}

final class WebCheckoutProductSelection {
  const WebCheckoutProductSelection({
    required this.productGlobalId,
    required this.quantity,
  });
  final String productGlobalId;
  final int quantity;
  Map<String, Object?> toJson() {
    if (productGlobalId.isEmpty || quantity < 1) {
      throw ArgumentError('Producto de checkout inválido.');
    }
    return {'productGlobalId': productGlobalId, 'quantity': quantity};
  }
}

final class WebCheckoutPaymentSelection {
  const WebCheckoutPaymentSelection({
    required this.method,
    required this.amountCents,
  });
  final String method;
  final int amountCents;
  Map<String, Object?> toJson() {
    if (method.trim().isEmpty || amountCents <= 0) {
      throw ArgumentError('Pago inválido.');
    }
    return {'method': method, 'amountCents': amountCents};
  }
}

final class WebComboCheckoutResult {
  const WebComboCheckoutResult({
    required this.saleGlobalId,
    required this.folio,
    required this.totalCents,
    required this.fifoCostCents,
    required this.alreadyProcessed,
    required this.saleDateTime,
  });
  final String saleGlobalId;
  final String folio;
  final int totalCents;
  final int fifoCostCents;
  final bool alreadyProcessed;
  final DateTime saleDateTime;

  factory WebComboCheckoutResult.fromJson(Map<String, Object?> json) =>
      WebComboCheckoutResult(
        saleGlobalId: json['saleGlobalId'] as String,
        folio: json['folio'] as String,
        totalCents: (json['totalCents'] as num).toInt(),
        fifoCostCents: (json['fifoCostCents'] as num).toInt(),
        alreadyProcessed: json['alreadyProcessed'] as bool,
        saleDateTime: DateTime.parse(json['saleDateTime'] as String),
      );
}

/// Mantener la misma idempotencyKey durante reintentos de una intención.
/// Crear una clave nueva únicamente al cambiar de carrito/intención comercial.
final class WebComboCheckoutRepository {
  const WebComboCheckoutRepository(this._api);
  final JsonApiClient _api;

  Future<WebComboCheckoutResult> checkout({
    required String idempotencyKey,
    required List<WebComboSelection> combos,
    required List<WebCheckoutPaymentSelection> payments,
    List<WebCheckoutProductSelection> products = const [],
    int? receivedCashCents,
  }) async {
    if (idempotencyKey.isEmpty || (combos.isEmpty && products.isEmpty) ||
        payments.isEmpty || (receivedCashCents != null && receivedCashCents < 0)) {
      throw ArgumentError('Solicitud de checkout inválida.');
    }
    final body = <String, Object?>{
      'idempotencyKey': idempotencyKey,
      'lines': products.map((e) => e.toJson()).toList(growable: false),
      'combos': combos.map((e) => e.toJson()).toList(growable: false),
      'payments': payments.map((e) => e.toJson()).toList(growable: false),
      if (receivedCashCents != null) 'receivedCashCents': receivedCashCents,
    };
    final result = await _api.post('/api/web/checkout', body);
    return WebComboCheckoutResult.fromJson(result);
  }
}
