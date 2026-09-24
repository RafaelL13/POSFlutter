import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';

void main() {
  group('CatalogImportCsv', () {
    test('parses canonical valid file', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Producto 1,Alimentos,Proveedor 1,100.00,140.00,10\n',
        ),
      );

      expect(preview.errors, isEmpty);
      expect(preview.rows, hasLength(1));

      final row = preview.rows.single;

      expect(row.sku, 'P001');
      expect(row.costCents, 10000);
      expect(row.priceCents, 14000);
      expect(row.quantity, 10);
      expect(preview.fingerprint, hasLength(64));
    });

    test('supports comma inside quoted product name', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\r\n'
          'P001,"ALIMENTO GANADO, 20 KG",Alimentos,Proveedor 1,100.00,140.00,10\r\n',
        ),
      );

      expect(preview.errors, isEmpty);
      expect(preview.rows.single.name, 'ALIMENTO GANADO, 20 KG');
    });

    test('supports escaped quotes inside quoted field', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,"Producto ""Premium""",Alimentos,Proveedor 1,100,140,10\n',
        ),
      );

      expect(preview.errors, isEmpty);
      expect(preview.rows.single.name, 'Producto "Premium"');
    });

    test('accepts UTF-8 text', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Melaza líquida,Nutrición,Proveedor México,100.00,140.00,10\n',
        ),
      );

      expect(preview.errors, isEmpty);
      expect(preview.rows.single.name, 'Melaza líquida');
      expect(preview.rows.single.category, 'Nutrición');
    });

    test('detects duplicate SKU ignoring case', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Uno,Categoria,Proveedor,10,20,1\n'
          'p001,Dos,Categoria,Proveedor,10,20,1\n',
        ),
      );

      expect(preview.isValid, isFalse);
      expect(
        preview.errors.any((error) => error.contains('SKU duplicado')),
        isTrue,
      );
    });

    test('rejects decimal initial quantity', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Uno,Categoria,Proveedor,10,20,1.5\n',
        ),
      );

      expect(preview.isValid, isFalse);
      expect(
        preview.errors.any((error) => error.contains('entero no negativo')),
        isTrue,
      );
    });

    test('rejects negative initial quantity', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Uno,Categoria,Proveedor,10,20,-1\n',
        ),
      );

      expect(preview.isValid, isFalse);
    });

    test('requires supplier only when initial stock is positive', () {
      final zero = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Uno,Categoria,,10,20,0\n',
        ),
      );

      expect(zero.errors, isEmpty);

      final positive = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Uno,Categoria,,10,20,1\n',
        ),
      );

      expect(positive.isValid, isFalse);
      expect(
        positive.errors.any((error) => error.contains('proveedor obligatorio')),
        isTrue,
      );
    });

    test('rejects malformed CSV', () {
      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,"Producto sin cerrar,Categoria,Proveedor,10,20,1\n',
        ),
      );

      expect(preview.isValid, isFalse);
      expect(preview.errors.single, contains('sin cerrar'));
    });

    test('same bytes produce same fingerprint', () {
      final bytes = utf8.encode(
        'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
        'P001,Uno,Categoria,Proveedor,10,20,1\n',
      );

      final first = CatalogImportCsv.parse(bytes);
      final second = CatalogImportCsv.parse(bytes);

      expect(first.fingerprint, second.fingerprint);
    });
  });
}
