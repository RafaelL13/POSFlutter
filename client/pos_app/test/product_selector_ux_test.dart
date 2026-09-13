import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/catalog/data/operational_catalog_repository.dart';
import 'package:pos_app/shared/presentation/product_selector.dart';

void main() {
  const products = <ProductOption>[
    ProductOption(
      id: 11,
      globalId: 'internal-global-id-11',
      code: 'CAF-250',
      name: 'Café molido',
      barcode: '750100000001',
      categoryName: 'Abarrotes',
      priceCents: 8990,
      stock: 8,
      active: true,
    ),
    ProductOption(
      id: 22,
      globalId: 'internal-global-id-22',
      code: 'CAF-500',
      name: 'Café molido',
      barcode: '750100000002',
      categoryName: 'Premium',
      priceCents: 14990,
      stock: 0,
      active: true,
    ),
  ];

  Future<void> pumpSelector(
    WidgetTester tester, {
    required ValueChanged<ProductOption?> onSelected,
    bool requireStock = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ProductSelector(
              products: products,
              onSelected: onSelected,
              onCreateProduct: () {},
              requireStock: requireStock,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('searches by product name and distinguishes duplicate names', (
    tester,
  ) async {
    await pumpSelector(tester, onSelected: (_) {});
    await tester.enterText(
      find.byKey(const Key('product-selector-field')),
      'Café molido',
    );
    await tester.pump();

    expect(find.text('Código: CAF-250'), findsOneWidget);
    expect(find.text('Código: CAF-500'), findsOneWidget);
    expect(find.text('Abarrotes'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text(r'$89.90'), findsOneWidget);
    expect(find.text(r'$149.90'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'searches by code and preserves the selected technical identity',
    (tester) async {
      ProductOption? selected;
      await pumpSelector(tester, onSelected: (value) => selected = value);
      await tester.enterText(
        find.byKey(const Key('product-selector-field')),
        'CAF-500',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('product-option-22')));
      await tester.pump();

      expect(selected?.id, 22);
      expect(selected?.globalId, 'internal-global-id-22');
      expect(find.textContaining('internal-global-id'), findsNothing);
      expect(find.textContaining('ProductId'), findsNothing);
      expect(find.textContaining('GlobalId'), findsNothing);
    },
  );

  testWidgets('free text never becomes a resolved product selection', (
    tester,
  ) async {
    ProductOption? selected;
    await pumpSelector(tester, onSelected: (value) => selected = value);
    await tester.enterText(
      find.byKey(const Key('product-selector-field')),
      'Producto inventado',
    );
    await tester.pump();

    expect(selected, isNull);
    expect(find.text('¿No existe? Crear producto'), findsOneWidget);
  });

  testWidgets(
    'barcode search works and unavailable product cannot be selected',
    (tester) async {
      ProductOption? selected;
      await pumpSelector(
        tester,
        onSelected: (value) => selected = value,
        requireStock: true,
      );
      await tester.enterText(
        find.byKey(const Key('product-selector-field')),
        '750100000002',
      );
      await tester.pump();

      expect(find.text('Agotado'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('product-option-22')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
