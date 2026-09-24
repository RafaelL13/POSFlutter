import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_xlsx.dart';

void main() {
  test('official CSV template is accepted by production parser', () {
    final bytes = File(
      r'C:\POSFlutter\docs\templates\plantilla_importacion_productos.csv',
    ).readAsBytesSync();

    final preview = CatalogImportCsv.parse(bytes);

    expect(preview.errors, isEmpty);
    expect(preview.rows, hasLength(2));

    expect(preview.rows[0].sku, 'P001');
    expect(preview.rows[0].costCents, 10000);
    expect(preview.rows[0].priceCents, 14000);
    expect(preview.rows[0].quantity, 10);
    expect(preview.rows[0].supplier, 'Proveedor Ejemplo');

    expect(preview.rows[1].sku, 'P002');
    expect(preview.rows[1].costCents, 5000);
    expect(preview.rows[1].priceCents, 7500);
    expect(preview.rows[1].quantity, 0);
    expect(preview.rows[1].supplier, isEmpty);
  });

  test('official XLSX template is accepted by production parser', () {
    final bytes = File(
      r'C:\POSFlutter\docs\templates\plantilla_importacion_productos.xlsx',
    ).readAsBytesSync();

    final preview = CatalogImportXlsx.parse(bytes);

    expect(preview.errors, isEmpty);
    expect(preview.rows, hasLength(2));

    expect(preview.rows[0].sku, 'P001');
    expect(preview.rows[0].costCents, 10000);
    expect(preview.rows[0].priceCents, 14000);
    expect(preview.rows[0].quantity, 10);
    expect(preview.rows[0].supplier, 'Proveedor Ejemplo');

    expect(preview.rows[1].sku, 'P002');
    expect(preview.rows[1].costCents, 5000);
    expect(preview.rows[1].priceCents, 7500);
    expect(preview.rows[1].quantity, 0);
    expect(preview.rows[1].supplier, isEmpty);
  });
}
