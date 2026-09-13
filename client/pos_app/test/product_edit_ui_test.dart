import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';

void main() {
  test('ProductOverview conserva datos necesarios para edición', () {
    const product = ProductOverview(
      id: 10,
      globalId: 'product-10',
      code: 'SKU-10',
      name: 'Camarón',
      barcode: '7501234567890',
      categoryId: 4,
      categoryName: 'Congelados',
      salePriceCents: 15900,
      minimumStock: 3,
      active: true,
      stock: 8,
    );

    expect(product.globalId, 'product-10');
    expect(product.barcode, '7501234567890');
    expect(product.categoryId, 4);
    expect(product.categoryName, 'Congelados');
    expect(product.active, isTrue);
    expect(product.stock, 8);
  });

  testWidgets('viewport reducido permite scroll sin RenderFlex overflow', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;

    FlutterError.onError = errors.add;

    addTearDown(() {
      FlutterError.onError = previous;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.physicalSize = const Size(800, 320);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TextField(),
                SizedBox(height: 16),
                TextField(),
                SizedBox(height: 16),
                TextField(),
                SizedBox(height: 16),
                SwitchListTile(
                  value: true,
                  onChanged: null,
                  title: Text('Producto activo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      errors.where(
        (error) => error.exceptionAsString().contains('RenderFlex overflowed'),
      ),
      isEmpty,
    );
  });
}
