enum PaymentMethod {
  cash('Cash'),
  card('Card'),
  transfer('Transfer');

  const PaymentMethod(this.storageValue);

  final String storageValue;

  static PaymentMethod fromStorage(String value) => switch (value) {
    'Cash' => cash,
    'Card' => card,
    'Transfer' => transfer,
    _ => throw ArgumentError.value(value, 'value', 'Método de pago inválido.'),
  };
}

final class SalePaymentInput {
  const SalePaymentInput({required this.method, required this.amountCents});

  final PaymentMethod method;
  final int amountCents;
}

final class SalePaymentRules {
  const SalePaymentRules._();

  static List<SalePaymentInput> validate(
    Iterable<SalePaymentInput> payments, {
    required int totalCents,
  }) {
    final normalized = payments.toList(growable: false);
    if (normalized.isEmpty) {
      throw StateError('La venta debe tener al menos un pago.');
    }
    if (normalized.any((payment) => payment.amountCents <= 0)) {
      throw StateError('Cada pago debe ser mayor que cero.');
    }
    if (normalized.map((payment) => payment.method).toSet().length !=
        normalized.length) {
      throw StateError('Cada método sólo puede aparecer una vez.');
    }
    final paid = normalized.fold<int>(
      0,
      (total, payment) => total + payment.amountCents,
    );
    if (paid != totalCents) {
      throw StateError('La suma de pagos debe coincidir con el total.');
    }
    return normalized;
  }

  static int cashCents(Iterable<SalePaymentInput> payments) => payments
      .where((payment) => payment.method == PaymentMethod.cash)
      .fold<int>(0, (total, payment) => total + payment.amountCents);

  static String legacySummary(Iterable<SalePaymentInput> payments) {
    final values = payments.toList(growable: false);
    return values.length == 1 ? values.single.method.storageValue : 'Mixed';
  }
}
