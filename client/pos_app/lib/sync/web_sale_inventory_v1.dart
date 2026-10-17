/// Pure payload validator. No DB updates or cursor acknowledgement occur here.
/// Intended for tests and a future guarded SQLite application path.
final class WebSaleInventoryV1 {
  WebSaleInventoryV1._();

  static Map<String, Object?> validate(
    Map<String, Object?> payload, {
    required String businessGlobalId,
    required String branchGlobalId,
  }) {
    String requiredId(Object? value) {
      if (value is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value) ||
          value == '00000000-0000-0000-0000-000000000000') {
        throw StateError('Invalid WebSaleInventory v1 identity.');
      }
      return value.toLowerCase();
    }

    if (payload['contractVersion'] != 1 ||
        requiredId(payload['businessGlobalId']) != requiredId(businessGlobalId) ||
        requiredId(payload['branchGlobalId']) != requiredId(branchGlobalId)) {
      throw StateError('Unsupported version or tenant/branch mismatch.');
    }
    requiredId(payload['globalId']);
    if (payload['date'] is! String || DateTime.tryParse(payload['date'] as String) == null) {
      throw StateError('Invalid event date.');
    }
    final lines = payload['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 100) {
      throw StateError('Invalid event lines.');
    }
    final products = <String>{};
    final allLots = <String>{};
    for (final raw in lines) {
      if (raw is! Map) throw StateError('Invalid line.');
      final line = Map<String, Object?>.from(raw);
      final product = requiredId(line['productGlobalId']);
      if (!products.add(product)) throw StateError('Duplicate product.');
      final quantity = line['quantity'];
      final lots = line['lots'];
      if (quantity is! int || quantity <= 0 || quantity > 100000 ||
          lots is! List || lots.isEmpty || lots.length > 100) {
        throw StateError('Invalid FIFO quantities.');
      }
      var sum = 0;
      for (final rawLot in lots) {
        if (rawLot is! Map) throw StateError('Invalid FIFO lot.');
        final lot = Map<String, Object?>.from(rawLot);
        final lotId = requiredId(lot['lotGlobalId']);
        if (!allLots.add(lotId)) throw StateError('Duplicate lot.');
        final taken = lot['quantity'];
        if (taken is! int || taken <= 0 || taken > quantity) {
          throw StateError('Invalid allocation quantity.');
        }
        sum += taken;
      }
      if (sum != quantity) throw StateError('FIFO allocation mismatch.');
    }
    return payload;
  }
}
