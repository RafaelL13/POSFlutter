import 'package:flutter/services.dart';

final class ProductImportNativeFile {
  const ProductImportNativeFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

abstract interface class ProductImportNativeFilePicker {
  Future<ProductImportNativeFile?> pickFile();
}

final class NativeSafProductImportFilePicker
    implements ProductImportNativeFilePicker {
  const NativeSafProductImportFilePicker();

  static const MethodChannel _channel = MethodChannel(
    'com.posflutter.pos_app/product_import_saf',
  );

  @override
  Future<ProductImportNativeFile?> pickFile() async {
    final result = await _channel.invokeMethod<Object?>('pickCatalogFile');

    if (result == null) {
      return null;
    }

    if (result is! Map) {
      throw StateError(
        'Android devolviÃ³ una respuesta invÃ¡lida al seleccionar el archivo.',
      );
    }

    final name = result['name'];
    final bytes = result['bytes'];

    if (name is! String || name.trim().isEmpty) {
      throw StateError(
        'Android no devolviÃ³ un nombre vÃ¡lido para el archivo seleccionado.',
      );
    }

    if (bytes is! Uint8List) {
      throw StateError(
        'Android no pudo leer el contenido del archivo seleccionado.',
      );
    }

    return ProductImportNativeFile(name: name, bytes: bytes);
  }
}
