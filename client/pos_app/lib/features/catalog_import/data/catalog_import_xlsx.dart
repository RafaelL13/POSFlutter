import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_validator.dart';

export 'catalog_import_validator.dart'
    show CatalogImportPreview, CatalogImportRow;

abstract final class CatalogImportXlsx {
  static CatalogImportPreview parse(List<int> bytes) {
    final fingerprint = sha256.convert(bytes).toString();

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      return CatalogImportPreview(const [], const [
        'El archivo XLSX no es valido.',
      ], fingerprint);
    }

    if (workbook.tables.isEmpty) {
      return CatalogImportPreview(const [], const [
        'El archivo esta vacio.',
      ], fingerprint);
    }

    final nonEmptySheets = workbook.tables.entries
        .where(
          (entry) => entry.value.rows.any(
            (row) => row.any((cell) => _cellText(cell).trim().isNotEmpty),
          ),
        )
        .toList(growable: false);

    if (nonEmptySheets.isEmpty) {
      return CatalogImportPreview(const [], const [
        'El archivo esta vacio.',
      ], fingerprint);
    }

    if (nonEmptySheets.length != 1) {
      return CatalogImportPreview(const [], const [
        'El archivo XLSX debe contener una sola hoja con datos.',
      ], fingerprint);
    }

    final sheet = nonEmptySheets.single.value;

    final records = sheet.rows
        .map((row) => row.map(_cellText).toList(growable: false))
        .toList(growable: false);

    return CatalogImportValidator.validate(
      records: records,
      sourceBytes: bytes,
    );
  }

  static String _cellText(Data? cell) {
    if (cell == null || cell.value == null) {
      return '';
    }

    final value = cell.value!;

    if (value is IntCellValue) {
      return value.value.toString();
    }

    if (value is DoubleCellValue) {
      final number = value.value;

      if (number.isFinite && number == number.truncateToDouble()) {
        return number.toInt().toString();
      }

      return number.toString();
    }

    if (value is TextCellValue) {
      return value.value.toString();
    }

    return value.toString();
  }
}
