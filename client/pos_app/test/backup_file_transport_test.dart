import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/backup/presentation/backup_file_transport.dart';

void main() {
  late Directory root;
  late Directory tempDirectory;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pos_backup_transport_');
    tempDirectory = Directory('${root.path}${Platform.pathSeparator}stage');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('exportBackup sends exact bytes and filename to gateway', () async {
    final source = File('${root.path}${Platform.pathSeparator}backup_test.db');
    final expectedBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    await source.writeAsBytes(expectedBytes, flush: true);

    final gateway = _FakeGateway(
      saveResult: Uri.parse('content://backup/backup_test.db'),
    );

    final transport = BackupFileTransport(
      gateway: gateway,
      temporaryDirectoryProvider: _FakeTemporaryDirectoryProvider(
        tempDirectory,
      ),
    );

    final exported = await transport.exportBackup(source.path);

    expect(exported, isTrue);
    expect(gateway.savedFileName, 'backup_test.db');
    expect(gateway.savedBytes, expectedBytes);
  });

  test('export cancellation preserves internal backup', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}backup_cancel.db',
    );
    await source.writeAsBytes(<int>[9, 8, 7], flush: true);

    final gateway = _FakeGateway(saveResult: null);

    final transport = BackupFileTransport(
      gateway: gateway,
      temporaryDirectoryProvider: _FakeTemporaryDirectoryProvider(
        tempDirectory,
      ),
    );

    final exported = await transport.exportBackup(source.path);

    expect(exported, isFalse);
    expect(await source.exists(), isTrue);
    expect(await source.readAsBytes(), <int>[9, 8, 7]);
  });

  test('restore selection cancellation creates no staged file', () async {
    final gateway = _FakeGateway(pickedFile: null);

    final transport = BackupFileTransport(
      gateway: gateway,
      temporaryDirectoryProvider: _FakeTemporaryDirectoryProvider(
        tempDirectory,
      ),
    );

    final staged = await transport.pickAndStageRestore();

    expect(staged, isNull);
    expect(await tempDirectory.exists(), isFalse);
  });

  test(
    'selected restore is copied to private staging and can be deleted',
    () async {
      final source = File('${root.path}${Platform.pathSeparator}selected.db');
      final expectedBytes = Uint8List.fromList(<int>[10, 20, 30, 40]);
      await source.writeAsBytes(expectedBytes, flush: true);

      final gateway = _FakeGateway(
        pickedFile: BackupPickedFile(name: '../selected.db', path: source.path),
      );

      final transport = BackupFileTransport(
        gateway: gateway,
        temporaryDirectoryProvider: _FakeTemporaryDirectoryProvider(
          tempDirectory,
        ),
      );

      final staged = await transport.pickAndStageRestore();

      expect(staged, isNotNull);
      expect(staged!.originalName, 'selected.db');
      expect(await staged.file.exists(), isTrue);
      expect(await staged.file.readAsBytes(), expectedBytes);
      expect(staged.file.path.startsWith(tempDirectory.path), isTrue);

      await staged.delete();

      expect(await staged.file.exists(), isFalse);
    },
  );

  test('restore rejects unavailable selected file', () async {
    final gateway = _FakeGateway(
      pickedFile: BackupPickedFile(
        name: 'missing.db',
        path: '${root.path}${Platform.pathSeparator}does_not_exist.db',
      ),
    );

    final transport = BackupFileTransport(
      gateway: gateway,
      temporaryDirectoryProvider: _FakeTemporaryDirectoryProvider(
        tempDirectory,
      ),
    );

    await expectLater(
      transport.pickAndStageRestore(),
      throwsA(isA<StateError>()),
    );

    expect(await tempDirectory.exists(), isFalse);
  });
}

final class _FakeGateway implements BackupFilePickerGateway {
  _FakeGateway({this.saveResult, this.pickedFile});

  final Uri? saveResult;
  final BackupPickedFile? pickedFile;

  String? savedFileName;
  Uint8List? savedBytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    savedFileName = fileName;
    savedBytes = Uint8List.fromList(bytes);
    return saveResult;
  }

  @override
  Future<BackupPickedFile?> pickBackupFile() async => pickedFile;
}

final class _FakeTemporaryDirectoryProvider
    implements BackupTemporaryDirectoryProvider {
  const _FakeTemporaryDirectoryProvider(this.directory);

  final Directory directory;

  @override
  Future<Directory> getTemporaryDirectory() async => directory;
}
