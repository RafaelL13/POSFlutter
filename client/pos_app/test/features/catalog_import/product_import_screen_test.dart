import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';
import 'package:pos_app/features/catalog_import/data/initial_inventory_repository.dart';
import 'package:pos_app/features/catalog_import/presentation/product_import_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProductImportScreen', () {
    testWidgets('valid CSV shows offline preview and inventory metrics', (
      tester,
    ) async {
      await _pumpScreen(tester, pickFile: () async => _csvFile(_validCsv));

      await _pick(tester);

      expect(find.text('Archivo: productos.csv'), findsOneWidget);
      expect(find.byKey(const Key('product-import-preview')), findsOneWidget);
      expect(
        find.byKey(const Key('product-import-validation-errors')),
        findsNothing,
      );
      expect(find.byKey(const Key('product-import-confirm')), findsOneWidget);

      expect(find.text('Productos válidos'), findsOneWidget);
      expect(find.text('Con existencia inicial'), findsOneWidget);
      expect(find.text('Unidades iniciales'), findsOneWidget);

      expect(find.text('2'), findsWidgets);
      expect(find.text('1'), findsWidgets);
      expect(find.text('10'), findsWidgets);
    });

    testWidgets('invalid CSV shows errors and cannot be confirmed', (
      tester,
    ) async {
      await _pumpScreen(tester, pickFile: () async => _csvFile(_invalidCsv));

      await _pick(tester);

      expect(
        find.byKey(const Key('product-import-validation-errors')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('product-import-preview')), findsNothing);
      expect(find.byKey(const Key('product-import-confirm')), findsNothing);
    });

    testWidgets('empty file reports read error', (tester) async {
      await _pumpScreen(
        tester,
        pickFile: () async =>
            ProductImportSelectedFile(name: 'vacio.csv', bytes: Uint8List(0)),
      );

      await _pick(tester);

      expect(
        find.byKey(const Key('product-import-load-error')),
        findsOneWidget,
      );
      expect(find.textContaining('vacío'), findsOneWidget);
      expect(find.byKey(const Key('product-import-confirm')), findsNothing);
    });

    testWidgets('cancel confirmation never invokes executor', (tester) async {
      var calls = 0;

      await _pumpScreen(
        tester,
        pickFile: () async => _csvFile(_validCsv),
        executeImport: ({required preview, required policy, sourceName}) async {
          calls++;
          return 'unexpected';
        },
      );

      await _pick(tester);
      await _openConfirmation(tester);

      expect(
        find.byKey(const Key('product-import-cancel-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('product-import-cancel-dialog')));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.byKey(const Key('product-import-preview')), findsOneWidget);
    });

    testWidgets('default policy passes skip to executor', (tester) async {
      var calls = 0;
      ExistingCatalogPolicy? receivedPolicy;
      String? receivedSource;

      await _pumpScreen(
        tester,
        pickFile: () async => _csvFile(_validCsv),
        executeImport: ({required preview, required policy, sourceName}) async {
          calls++;
          receivedPolicy = policy;
          receivedSource = sourceName;
          return 'import-skip-gid';
        },
      );

      await _pick(tester);
      await _openConfirmation(tester);
      await _acceptConfirmation(tester);

      expect(calls, 1);
      expect(receivedPolicy, ExistingCatalogPolicy.skip);
      expect(receivedSource, 'productos.csv');
      expect(find.text('Importación completada'), findsOneWidget);
      expect(find.textContaining('import-skip-gid'), findsOneWidget);
    });

    testWidgets(
      'update policy is passed exactly once and success resets state',
      (tester) async {
        var calls = 0;
        CatalogImportPreview? receivedPreview;
        ExistingCatalogPolicy? receivedPolicy;
        String? receivedSource;

        await _pumpScreen(
          tester,
          pickFile: () async => _csvFile(_validCsv),
          executeImport:
              ({required preview, required policy, sourceName}) async {
                calls++;
                receivedPreview = preview;
                receivedPolicy = policy;
                receivedSource = sourceName;
                return 'import-update-gid';
              },
        );

        await _pick(tester);

        final updatePolicy = find.byKey(
          const Key('product-import-policy-update'),
        );

        await tester.ensureVisible(updatePolicy);
        await tester.tap(updatePolicy);
        await tester.pumpAndSettle();

        await _openConfirmation(tester);
        await _acceptConfirmation(tester);

        expect(calls, 1);
        expect(receivedPreview, isNotNull);
        expect(receivedPreview!.isValid, isTrue);
        expect(receivedPreview!.rows.length, 2);
        expect(receivedPolicy, ExistingCatalogPolicy.updateCatalogData);
        expect(receivedSource, 'productos.csv');

        expect(find.text('Importación completada'), findsOneWidget);
        expect(find.textContaining('import-update-gid'), findsOneWidget);

        await tester.tap(find.byKey(const Key('product-import-success-close')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('product-import-preview')), findsNothing);
        expect(find.byKey(const Key('product-import-file-name')), findsNothing);
        expect(find.byKey(const Key('product-import-confirm')), findsNothing);
      },
    );
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ProductImportFilePicker pickFile,
  ProductImportExecutor? executeImport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProductImportScreen(
        pickFile: pickFile,
        executeImport: executeImport,
      ),
    ),
  );

  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester) async {
  final button = find.byKey(const Key('product-import-pick-file'));

  expect(button, findsOneWidget);

  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _openConfirmation(WidgetTester tester) async {
  final button = find.byKey(const Key('product-import-confirm'));

  expect(button, findsOneWidget);

  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('product-import-accept-dialog')), findsOneWidget);
}

Future<void> _acceptConfirmation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('product-import-accept-dialog')));

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

ProductImportSelectedFile _csvFile(String source) => ProductImportSelectedFile(
  name: 'productos.csv',
  bytes: Uint8List.fromList(utf8.encode(source)),
);

const _validCsv = '''
SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial
P001,Producto Uno,General,Proveedor Uno,100.00,140.00,10
P002,Producto Dos,General,,50.00,80.00,0
''';

const _invalidCsv = '''
SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial
P001,Producto Uno,General,,100.00,140.00,10
''';
