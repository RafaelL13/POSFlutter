import 'package:crypto/crypto.dart';

final class CatalogImportRow {
  const CatalogImportRow({
    required this.sku,
    required this.name,
    required this.category,
    required this.supplier,
    required this.costCents,
    required this.priceCents,
    required this.quantity,
  });

  final String sku;
  final String name;
  final String category;
  final String supplier;
  final int costCents;
  final int priceCents;
  final int quantity;
}

final class CatalogImportPreview {
  const CatalogImportPreview(this.rows, this.errors, this.fingerprint);

  final List<CatalogImportRow> rows;
  final List<String> errors;
  final String fingerprint;

  bool get isValid => errors.isEmpty && rows.isNotEmpty;
}

abstract final class CatalogImportValidator {
  static const requiredColumns = <String>[
    'SKU',
    'Producto',
    'Categoria',
    'Proveedor',
    'CostoCompra',
    'PrecioVenta',
    'ExistenciaInicial',
  ];

  static CatalogImportPreview validate({
    required List<List<String>> records,
    required List<int> sourceBytes,
  }) {
    final fingerprint = sha256.convert(sourceBytes).toString();

    final nonEmptyRecords = records
        .where((row) => row.any((value) => value.trim().isNotEmpty))
        .toList(growable: false);

    if (nonEmptyRecords.isEmpty) {
      return CatalogImportPreview(const [], const [
        'El archivo esta vacio.',
      ], fingerprint);
    }

    final header = nonEmptyRecords.first
        .map((value) => value.trim())
        .toList(growable: false);

    if (!_sameColumns(header, requiredColumns)) {
      return CatalogImportPreview(const [], [
        'Las columnas deben ser: ${requiredColumns.join(', ')}.',
      ], fingerprint);
    }

    final rows = <CatalogImportRow>[];
    final errors = <String>[];
    final seenSku = <String>{};

    for (var index = 1; index < nonEmptyRecords.length; index++) {
      final values = nonEmptyRecords[index];
      final rowNumber = index + 1;

      if (values.length != requiredColumns.length) {
        errors.add('Fila $rowNumber: numero de columnas invalido.');
        continue;
      }

      final sku = values[0].trim();
      final name = values[1].trim();
      final category = values[2].trim();
      final supplier = values[3].trim();

      final cost = _money(values[4]);
      final price = _money(values[5]);
      final quantityText = values[6].trim();
      final quantity = int.tryParse(quantityText);

      var valid = true;

      if (sku.isEmpty || name.isEmpty || category.isEmpty) {
        errors.add(
          'Fila $rowNumber: SKU, producto y categoria son obligatorios.',
        );
        valid = false;
      }

      final normalizedSku = sku.toUpperCase();
      if (sku.isNotEmpty && !seenSku.add(normalizedSku)) {
        errors.add('Fila $rowNumber: SKU duplicado ($sku).');
        valid = false;
      }

      if (cost == null || cost < 0) {
        errors.add('Fila $rowNumber: costo invalido.');
        valid = false;
      }

      if (price == null || price < 0) {
        errors.add('Fila $rowNumber: precio invalido.');
        valid = false;
      }

      if (quantity == null || quantity < 0) {
        errors.add(
          'Fila $rowNumber: existencia debe ser un entero no negativo.',
        );
        valid = false;
      }

      if (quantity != null && quantity > 0 && supplier.isEmpty) {
        errors.add(
          'Fila $rowNumber: proveedor obligatorio cuando hay existencia inicial.',
        );
        valid = false;
      }

      if (valid) {
        rows.add(
          CatalogImportRow(
            sku: sku,
            name: name,
            category: category,
            supplier: supplier,
            costCents: cost!,
            priceCents: price!,
            quantity: quantity!,
          ),
        );
      }
    }

    return CatalogImportPreview(
      List.unmodifiable(rows),
      List.unmodifiable(errors),
      fingerprint,
    );
  }

  static int? _money(String value) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,2}))?\s*$').firstMatch(value);

    if (match == null) {
      return null;
    }

    final pesos = int.parse(match.group(1)!);
    final decimals = (match.group(2) ?? '').padRight(2, '0');

    return pesos * 100 + int.parse(decimals);
  }

  static bool _sameColumns(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) {
      return false;
    }

    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }

    return true;
  }
}
