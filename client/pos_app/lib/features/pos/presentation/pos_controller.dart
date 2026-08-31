import 'package:flutter/foundation.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/features/pos/data/pos_catalog_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';

typedef PosBootstrapLoader = Future<PosBootstrap> Function();
typedef PosSaleCompleter = Future<CompletedSale> Function(
  List<CartLine> lines, {
  required String paymentMethod,
  int discountCents,
  int? receivedCents,
  SpecialAuthorizationGrant? authorizationGrant,
});

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
  bool loading = true;
  bool isSubmitting = false;
  String? error;

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
              product.code.toLowerCase().contains(query);
          return categoryMatches && queryMatches;
        })
        .toList(growable: false);
  }

  SaleTotals get totals =>
      calculateSaleTotals(lines, discountCents: discountCents);
  int get changeCents =>
      receivedCents > totals.totalCents ? receivedCents - totals.totalCents : 0;
  bool get canCheckout =>
      lines.isNotEmpty &&
      bootstrap?.cashOpen == true &&
      receivedCents >= totals.totalCents &&
      !isSubmitting;

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
      receivedCents = 0;
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

  void setReceivedCents(int value) {
    receivedCents = value < 0 ? 0 : value;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    discountCents = 0;
    receivedCents = 0;
    notifyListeners();
  }

  Future<CompletedSale?> submit({
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    if (!canCheckout) return null;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      final sale = await _completeSale(
        List<CartLine>.unmodifiable(lines),
        paymentMethod: 'Cash',
        discountCents: discountCents,
        receivedCents: receivedCents,
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
}
