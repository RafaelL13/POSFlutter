import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class BackupFilePickerGateway {
  Future<Uri?> saveFile({required String fileName, required Uint8List bytes});

  Future<BackupPickedFile?> pickBackupFile();
}

final class BackupPickedFile {
  const BackupPickedFile({required this.name, required this.path});

  final String name;
  final String? path;
}

final class NativeSafBackupGateway implements BackupFilePickerGateway {
  const NativeSafBackupGateway();

  static const MethodChannel _channel = MethodChannel(
    'com.posflutter.pos_app/backup_saf',
  );

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final uri = await _channel.invokeMethod<String>(
      'saveBackup',
      <String, Object>{'fileName': fileName, 'bytes': bytes},
    );

    return uri == null ? null : Uri.parse(uri);
  }

  @override
  Future<BackupPickedFile?> pickBackupFile() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickBackup',
    );

    if (result == null) return null;

    final name = result['name'];
    final path = result['path'];

    if (name is! String || name.isEmpty || path is! String || path.isEmpty) {
      throw StateError('Android devolviÃ³ un respaldo invÃ¡lido.');
    }

    return BackupPickedFile(name: name, path: path);
  }
}

abstract interface class BackupTemporaryDirectoryProvider {
  Future<Directory> getTemporaryDirectory();
}

final class PathProviderBackupTemporaryDirectoryProvider
    implements BackupTemporaryDirectoryProvider {
  const PathProviderBackupTemporaryDirectoryProvider();

  @override
  Future<Directory> getTemporaryDirectory() => pathProviderTemporaryDirectory();
}

Future<Directory> pathProviderTemporaryDirectory() => getTemporaryDirectory();

final class BackupFileTransport {
  BackupFileTransport({
    BackupFilePickerGateway? gateway,
    BackupTemporaryDirectoryProvider? temporaryDirectoryProvider,
  }) : _gateway = gateway ?? const NativeSafBackupGateway(),
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ??
           const PathProviderBackupTemporaryDirectoryProvider();

  final BackupFilePickerGateway _gateway;
  final BackupTemporaryDirectoryProvider _temporaryDirectoryProvider;

  Future<bool> exportBackup(String sourcePath) async {
    final source = File(sourcePath);

    if (!await source.exists()) {
      throw StateError('El respaldo interno no existe.');
    }

    final bytes = await source.readAsBytes();

    if (bytes.isEmpty) {
      throw StateError('El respaldo interno estÃ¡ vacÃ­o.');
    }

    final result = await _gateway.saveFile(
      fileName: p.basename(sourcePath),
      bytes: bytes,
    );

    return result != null;
  }

  Future<StagedBackupFile?> pickAndStageRestore() async {
    final selected = await _gateway.pickBackupFile();

    if (selected == null) return null;

    final selectedPath = selected.path;

    if (selectedPath == null || selectedPath.isEmpty) {
      throw StateError('No fue posible acceder al respaldo seleccionado.');
    }

    final source = File(selectedPath);

    if (!await source.exists()) {
      throw StateError('El respaldo seleccionado no estÃ¡ disponible.');
    }

    final bytes = await source.readAsBytes();

    if (bytes.isEmpty) {
      throw StateError('El respaldo seleccionado estÃ¡ vacÃ­o.');
    }

    final directory = await _temporaryDirectoryProvider.getTemporaryDirectory();
    await directory.create(recursive: true);

    final safeName = p.basename(selected.name);
    final stagedFile = File(
      p.join(
        directory.path,
        'restore_${DateTime.now().toUtc().microsecondsSinceEpoch}_$safeName',
      ),
    );

    await stagedFile.writeAsBytes(bytes, flush: true);

    // The Android SAF bridge returns its own temporary cache copy.
    // Once staged in the transport-owned location, that bridge copy
    // is no longer required.
    if (source.path != stagedFile.path) {
      try {
        await source.delete();
      } on FileSystemException {
        // The staged copy is authoritative from this point forward.
      }
    }

    return StagedBackupFile(file: stagedFile, originalName: safeName);
  }
}

final class StagedBackupFile {
  const StagedBackupFile({required this.file, required this.originalName});

  final File file;
  final String originalName;

  Future<void> delete() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
