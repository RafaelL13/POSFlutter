import 'package:flutter/foundation.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/features/payments/domain/sale_payment.dart';
import 'package:pos_app/features/pos/data/pos_catalog_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';

typedef PosBootstrapLoader = Future<PosBootstrap> Function();
typedef PosSaleCompleter = Future<CompletedSale> Function(
  List<CartLine> lines, {
  required List<SalePaymentInput> payments,
  int discountCents,
  int? receivedCents,
  SpecialAuthorizationGrant? authorizationGrant,
});

enum PosPaymentMode { cash, card, transfer, mixed }

final class PosController extends ChangeNotifier {
  PosController({
    required PosBootstrapLoader load,
    required PosSaleCompleter completeSale,
  }) : this._(load, completeSale);

  PosController._(this._load, this._completeSale);

  final PosBootstrapLoader _load;
  final PosSaleCompleter _completeSale;

  PosBootstrap? bootstrap;
  final List<CartLine> lines = [];
  String searchQuery = '';
  int? selectedCategoryId;
  int discountCents = 0;
  int receivedCents = 0;
  int mixedCashCents = 0;
  int mixedCardCents = 0;
  int mixedTransferCents = 0;
  PosPaymentMode paymentMode = PosPaymentMode.cash;
  bool loading = true;
  bool isSubmitting = false;
  String? error;
  int _paymentInputRevision = 0;

  int get paymentInputRevision => _paymentInputRevision;

  List<PosProduct> get visibleProducts {
    final query = searchQuery.trim().toLowerCase();
    return (bootstrap?.products ?? const <PosProduct>[])
        .where((product) {
          final categoryMatches =
              selectedCategoryId == null ||
              product.categoryId == selectedCategoryId;
          final queryMatches =
              query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              product.code.toLowerCase().contains(query) ||
              (product.barcode?.toLowerCase().contains(query) ?? false);
          return categoryMatches && queryMatches;
        })
        .toList(growable: false);
  }

  SaleTotals get totals =>
      calculateSaleTotals(lines, discountCents: discountCents);

  int get cashPaymentCents => switch (paymentMode) {
    PosPaymentMode.cash => totals.totalCents,
    PosPaymentMode.card => 0,
    PosPaymentMode.transfer => 0,
    PosPaymentMode.mixed => mixedCashCents,
  };

  int get allocatedPaymentCents => switch (paymentMode) {
    PosPaymentMode.cash => totals.totalCents,
    PosPaymentMode.card => totals.totalCents,
    PosPaymentMode.transfer => totals.totalCents,
    PosPaymentMode.mixed =>
      mixedCashCents + mixedCardCents + mixedTransferCents,
  };

  int get paymentDifferenceCents => totals.totalCents - allocatedPaymentCents;

  int get positiveMixedMethodCount => [
    mixedCashCents,
    mixedCardCents,
    mixedTransferCents,
  ].where((amount) => amount > 0).length;

  int get changeCents =>
      cashPaymentCents > 0 && receivedCents > cashPaymentCents
      ? receivedCents - cashPaymentCents
      : 0;

  List<SalePaymentInput> get paymentInputs => switch (paymentMode) {
    PosPaymentMode.cash => [
      SalePaymentInput(
        method: PaymentMethod.cash,
        amountCents: totals.totalCents,
      ),
    ],
    PosPaymentMode.card => [
      SalePaymentInput(
        method: PaymentMethod.card,
        amountCents: totals.totalCents,
      ),
    ],
    PosPaymentMode.transfer => [
      SalePaymentInput(
        method: PaymentMethod.transfer,
        amountCents: totals.totalCents,
      ),
    ],
    PosPaymentMode.mixed => [
      if (mixedCashCents > 0)
        SalePaymentInput(
          method: PaymentMethod.cash,
          amountCents: mixedCashCents,
        ),
      if (mixedCardCents > 0)
        SalePaymentInput(
          method: PaymentMethod.card,
          amountCents: mixedCardCents,
        ),
      if (mixedTransferCents > 0)
        SalePaymentInput(
          method: PaymentMethod.transfer,
          amountCents: mixedTransferCents,
        ),
    ],
  };

  String? get checkoutBlockReason {
    if (lines.isEmpty) {
      return 'Agrega al menos un producto para cobrar.';
    }
    if (totals.totalCents <= 0) {
      return 'El total de la venta debe ser mayor que cero.';
    }
    if (bootstrap?.cashOpen != true) {
      return 'Abre caja para comenzar el turno y registrar ventas.';
    }
    if (paymentMode == PosPaymentMode.mixed) {
      if (positiveMixedMethodCount < 2) {
        return 'El pago mixto requiere al menos dos formas de pago.';
      }
      if (paymentDifferenceCents > 0) {
        return 'Falta asignar parte del total entre las formas de pago.';
      }
      if (paymentDifferenceCents < 0) {
        return 'La suma de pagos excede el total de la venta.';
      }
    }
    if (cashPaymentCents > 0 && receivedCents < cashPaymentCents) {
      return 'El efectivo recibido debe cubrir la parte pagada en efectivo.';
    }
    return null;
  }

  bool get canCheckout => checkoutBlockReason == null && !isSubmitting;

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      bootstrap = await _load();
    } on Object {
      error = 'No se pudieron cargar los productos locales.';
    }
    loading = false;
    notifyListeners();
  }

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void selectCategory(int? id) {
    selectedCategoryId = id;
    notifyListeners();
  }

  bool addProduct(PosProduct product) {
    if (product.stock <= 0) return false;
    final index = lines.indexWhere((line) => line.productId == product.id);
    if (index >= 0) return increment(lines[index]);
    lines.add(
      CartLine(
        productId: product.id,
        productGlobalId: product.globalId,
        name: product.name,
        quantity: 1,
        unitPriceCents: product.priceCents,
        availableStock: product.stock,
      ),
    );
    notifyListeners();
    return true;
  }

  bool increment(CartLine line) {
    if (line.availableStock != null && line.quantity >= line.availableStock!) {
      return false;
    }
    line.quantity++;
    notifyListeners();
    return true;
  }

  void decrement(CartLine line) {
    if (line.quantity > 1) {
      line.quantity--;
      notifyListeners();
    }
  }

  void remove(CartLine line) {
    lines.remove(line);
    if (lines.isEmpty) {
      discountCents = 0;
      _resetPaymentState();
    }
    notifyListeners();
  }

  bool setQuantity(CartLine line, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null ||
        parsed < 1 ||
        (line.availableStock != null && parsed > line.availableStock!)) {
      return false;
    }
    line.quantity = parsed;
    notifyListeners();
    return true;
  }

  bool setDiscount(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > totals.subtotalCents) {
      return false;
    }
    discountCents = parsed;
    notifyListeners();
    return true;
  }

  void setPaymentMode(PosPaymentMode value) {
    if (paymentMode == value) return;
    paymentMode = value;
    receivedCents = 0;
    mixedCashCents = 0;
    mixedCardCents = 0;
    mixedTransferCents = 0;
    _paymentInputRevision++;
    notifyListeners();
  }

  void setReceivedCents(int value) {
    receivedCents = value < 0 ? 0 : value;
    notifyListeners();
  }

  void setReceivedExact() {
    receivedCents = cashPaymentCents;
    _paymentInputRevision++;
    notifyListeners();
  }

  void setMixedPaymentCents(PaymentMethod method, int value) {
    final amount = value < 0 ? 0 : value;
    switch (method) {
      case PaymentMethod.cash:
        mixedCashCents = amount;
        break;
      case PaymentMethod.card:
        mixedCardCents = amount;
        break;
      case PaymentMethod.transfer:
        mixedTransferCents = amount;
        break;
    }
    notifyListeners();
  }

  void fillMixedRemaining(PaymentMethod method) {
    if (paymentMode != PosPaymentMode.mixed) return;
    final others = switch (method) {
      PaymentMethod.cash => mixedCardCents + mixedTransferCents,
      PaymentMethod.card => mixedCashCents + mixedTransferCents,
      PaymentMethod.transfer => mixedCashCents + mixedCardCents,
    };
    final remaining = totals.totalCents - others;
    final value = remaining > 0 ? remaining : 0;
    switch (method) {
      case PaymentMethod.cash:
        mixedCashCents = value;
        break;
      case PaymentMethod.card:
        mixedCardCents = value;
        break;
      case PaymentMethod.transfer:
        mixedTransferCents = value;
        break;
    }
    _paymentInputRevision++;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    discountCents = 0;
    _resetPaymentState();
    notifyListeners();
  }

  Future<CompletedSale?> submit({
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    if (!canCheckout) return null;

    final validPayments = SalePaymentRules.validate(
      paymentInputs,
      totalCents: totals.totalCents,
    );
    final cashCents = SalePaymentRules.cashCents(validPayments);

    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      final sale = await _completeSale(
        List<CartLine>.unmodifiable(lines),
        payments: validPayments,
        discountCents: discountCents,
        receivedCents: cashCents == 0 ? null : receivedCents,
        authorizationGrant: authorizationGrant,
      );
      clear();
      return sale;
    } on AdditionalAuthorizationRequiredException {
      rethrow;
    } on Object {
      error = 'No se pudo completar la venta.';
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  void _resetPaymentState() {
    paymentMode = PosPaymentMode.cash;
    receivedCents = 0;
    mixedCashCents = 0;
    mixedCardCents = 0;
    mixedTransferCents = 0;
    _paymentInputRevision++;
  }
}
