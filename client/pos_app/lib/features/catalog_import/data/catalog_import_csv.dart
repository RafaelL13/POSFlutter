import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_validator.dart';

export 'catalog_import_validator.dart'
    show CatalogImportPreview, CatalogImportRow;

abstract final class CatalogImportCsv {
  static const template =
      'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
      'P001,Producto ejemplo,Categoria ejemplo,Proveedor ejemplo,100.00,140.00,10\n';

  static CatalogImportPreview parse(List<int> bytes) {
    final fingerprint = sha256.convert(bytes).toString();

    final String text;
    try {
      text = utf8
          .decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '');
    } on FormatException {
      return CatalogImportPreview(const [], const [
        'El archivo no contiene texto UTF-8 valido.',
      ], fingerprint);
    }

    final records = _parseCsv(text);

    if (records.error != null) {
      return CatalogImportPreview(const [], [records.error!], fingerprint);
    }

    return CatalogImportValidator.validate(
      records: records.rows,
      sourceBytes: bytes,
    );
  }

  static _CsvParseResult _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;

    void finishField() {
      row.add(field.toString());
      field = StringBuffer();
    }

    void finishRow() {
      finishField();
      rows.add(row);
      row = <String>[];
    }

    for (var index = 0; index < input.length; index++) {
      final char = input[index];

      if (quoted) {
        if (char == '"') {
          if (index + 1 < input.length && input[index + 1] == '"') {
            field.write('"');
            index++;
          } else {
            quoted = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }

      if (char == '"') {
        if (field.isNotEmpty) {
          return const _CsvParseResult(
            [],
            'CSV invalido: comillas inesperadas.',
          );
        }
        quoted = true;
        continue;
      }

      if (char == ',') {
        finishField();
        continue;
      }

      if (char == '\r') {
        if (index + 1 < input.length && input[index + 1] == '\n') {
          index++;
        }
        finishRow();
        continue;
      }

      if (char == '\n') {
        finishRow();
        continue;
      }

      field.write(char);
    }

    if (quoted) {
      return const _CsvParseResult(
        [],
        'CSV invalido: campo entre comillas sin cerrar.',
      );
    }

    if (field.isNotEmpty || row.isNotEmpty) {
      finishRow();
    }

    return _CsvParseResult(rows, null);
  }
}

final class _CsvParseResult {
  const _CsvParseResult(this.rows, this.error);

  final List<List<String>> rows;
  final String? error;
}
