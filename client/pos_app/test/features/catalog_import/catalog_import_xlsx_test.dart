import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_xlsx.dart';

void main() {
  List<int> workbookBytes(
    List<List<Object?>> rows, {
    bool secondSheet = false,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    if (defaultSheet != null && defaultSheet != 'Productos') {
      excel.rename(defaultSheet, 'Productos');
    }

    final sheet = excel['Productos'];

    for (final row in rows) {
      sheet.appendRow(
        row
            .map<CellValue?>((value) {
              if (value == null) {
                return null;
              }
              if (value is int) {
                return IntCellValue(value);
              }
              if (value is double) {
                return DoubleCellValue(value);
              }
              return TextCellValue(value.toString());
            })
            .toList(growable: false),
      );
    }

    if (secondSheet) {
      excel['Otra'].appendRow([TextCellValue('datos')]);
    }

    final bytes = excel.encode();
    expect(bytes, isNotNull);
    return bytes!;
  }

  const header = <Object?>[
    'SKU',
    'Producto',
    'Categoria',
    'Proveedor',
    'CostoCompra',
    'PrecioVenta',
    'ExistenciaInicial',
  ];

  test('parses canonical XLSX with integer cents and stock', () {
    final bytes = workbookBytes([
      header,
      [
        'P001',
        'Producto ejemplo',
        'Categoria ejemplo',
        'Proveedor ejemplo',
        100,
        140,
        10,
      ],
    ]);

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.errors, isEmpty);
    expect(preview.isValid, isTrue);
    expect(preview.rows, hasLength(1));

    final row = preview.rows.single;

    expect(row.sku, 'P001');
    expect(row.costCents, 10000);
    expect(row.priceCents, 14000);
    expect(row.quantity, 10);
  });

  test('supports UTF-8 text in XLSX', () {
    final bytes = workbookBytes([
      header,
      [
        'CAM-001',
        'Camarón premium',
        'Mariscos',
        'Proveedor Águila',
        '125.50',
        '199.99',
        4,
      ],
    ]);

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.errors, isEmpty);
    expect(preview.rows.single.name, 'Camarón premium');
    expect(preview.rows.single.supplier, 'Proveedor Águila');
    expect(preview.rows.single.costCents, 12550);
    expect(preview.rows.single.priceCents, 19999);
  });

  test('rejects duplicate SKU case-insensitively', () {
    final bytes = workbookBytes([
      header,
      ['P001', 'Uno', 'Cat', '', 10, 20, 0],
      ['p001', 'Dos', 'Cat', '', 10, 20, 0],
    ]);

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.isValid, isFalse);
    expect(
      preview.errors.any((error) => error.contains('SKU duplicado')),
      isTrue,
    );
  });

  test('rejects decimal initial quantity', () {
    final bytes = workbookBytes([
      header,
      ['P001', 'Uno', 'Cat', 'Proveedor', 10, 20, 1.5],
    ]);

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.isValid, isFalse);
    expect(
      preview.errors.any((error) => error.contains('entero no negativo')),
      isTrue,
    );
  });

  test('requires supplier only when initial stock is positive', () {
    final zeroBytes = workbookBytes([
      header,
      ['P001', 'Sin stock', 'Cat', '', 10, 20, 0],
    ]);

    final positiveBytes = workbookBytes([
      header,
      ['P002', 'Con stock', 'Cat', '', 10, 20, 1],
    ]);

    final zero = CatalogImportXlsx.parse(zeroBytes);
    final positive = CatalogImportXlsx.parse(positiveBytes);

    expect(zero.isValid, isTrue);
    expect(positive.isValid, isFalse);
    expect(
      positive.errors.any((error) => error.contains('proveedor obligatorio')),
      isTrue,
    );
  });

  test('rejects invalid headers', () {
    final bytes = workbookBytes([
      [
        'Codigo',
        'Producto',
        'Categoria',
        'Proveedor',
        'CostoCompra',
        'PrecioVenta',
        'ExistenciaInicial',
      ],
      ['P001', 'Uno', 'Cat', 'Proveedor', 10, 20, 1],
    ]);

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.isValid, isFalse);
    expect(
      preview.errors.any((error) => error.contains('Las columnas deben ser')),
      isTrue,
    );
  });

  test('rejects workbook with multiple non-empty sheets', () {
    final bytes = workbookBytes([
      header,
      ['P001', 'Uno', 'Cat', 'Proveedor', 10, 20, 1],
    ], secondSheet: true);

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.isValid, isFalse);
    expect(
      preview.errors,
      contains('El archivo XLSX debe contener una sola hoja con datos.'),
    );
  });

  test('rejects malformed XLSX bytes', () {
    final preview = CatalogImportXlsx.parse([0, 1, 2, 3, 4]);

    expect(preview.isValid, isFalse);
    expect(preview.errors, contains('El archivo XLSX no es valido.'));
  });

  test('fingerprint is deterministic for identical bytes', () {
    final bytes = workbookBytes([
      header,
      ['P001', 'Uno', 'Cat', 'Proveedor', 10, 20, 1],
    ]);

    final first = CatalogImportXlsx.parse(bytes);
    final second = CatalogImportXlsx.parse(bytes);

    expect(first.fingerprint, second.fingerprint);
    expect(first.fingerprint, hasLength(64));
  });
}
