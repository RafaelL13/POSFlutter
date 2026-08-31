import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/pos/data/pos_catalog_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/features/pos/presentation/pos_controller.dart';
import 'package:pos_app/features/pos/presentation/pos_screen.dart';
import 'package:pos_app/sync/sync_health.dart';

void main() {
  test('search and category filters use local product fields', () async {
    final controller = await _controller();
    controller.setSearch('café');
    expect(controller.visibleProducts.single.name, 'Café americano');
    controller.setSearch('');
    controller.selectCategory(2);
    expect(controller.visibleProducts.map((item) => item.name), ['Agua']);
  });

  test(
    'tap product adds one and repeated tap increments existing line',
    () async {
      final controller = await _controller();
      expect(controller.addProduct(controller.visibleProducts.first), isTrue);
      expect(controller.addProduct(controller.visibleProducts.first), isTrue);
      expect(controller.lines, hasLength(1));
      expect(controller.lines.single.quantity, 2);
    },
  );

  test(
    'quantity controls decrement and remove without fractional values',
    () async {
      final controller = await _controller();
      controller.addProduct(controller.visibleProducts.first);
      controller.increment(controller.lines.single);
      controller.decrement(controller.lines.single);
      expect(controller.lines.single.quantity, 1);
      expect(controller.setQuantity(controller.lines.single, '1.5'), isFalse);
      expect(controller.setQuantity(controller.lines.single, '0'), isFalse);
      controller.remove(controller.lines.single);
      expect(controller.lines, isEmpty);
    },
  );

  test('out of stock and stock limit are denied', () async {
    final controller = await _controller();
    expect(controller.addProduct(controller.visibleProducts.last), isFalse);
    final product = controller.visibleProducts.first;
    controller.addProduct(product);
    expect(
      controller.setQuantity(controller.lines.single, '${product.stock + 1}'),
      isFalse,
    );
    expect(
      controller.setQuantity(controller.lines.single, '${product.stock}'),
      isTrue,
    );
    expect(controller.increment(controller.lines.single), isFalse);
  });

  test(
    'subtotal discount total cash and change remain integer cents',
    () async {
      final controller = await _controller();
      controller.addProduct(controller.visibleProducts.first);
      controller.increment(controller.lines.single);
      expect(controller.totals.subtotalCents, 9000);
      expect(controller.setDiscount('1000'), isTrue);
      expect(controller.totals.totalCents, 8000);
      controller.setReceivedCents(10000);
      expect(controller.changeCents, 2000);
      expect(controller.canCheckout, isTrue);
    },
  );

  test('closed cash blocks checkout before repository submission', () async {
    var calls = 0;
    final controller = await _controller(
      cashOpen: false,
      onComplete: (_) async {
        calls++;
        return const CompletedSale('sale', 1, 1);
      },
    );
    controller.addProduct(controller.visibleProducts.first);
    controller.setReceivedCents(10000);
    expect(controller.canCheckout, isFalse);
    expect(await controller.submit(), isNull);
    expect(calls, 0);
  });

  test('double submit is blocked and success clears cart', () async {
    final pending = Completer<CompletedSale>();
    var calls = 0;
    final controller = await _controller(
      onComplete: (_) {
        calls++;
        return pending.future;
      },
    );
    controller.addProduct(controller.visibleProducts.first);
    controller.setReceivedCents(10000);
    final first = controller.submit();
    final second = await controller.submit();
    expect(second, isNull);
    expect(calls, 1);
    pending.complete(const CompletedSale('sale-1', 4500, 2000));
    expect((await first)?.globalId, 'sale-1');
    expect(controller.lines, isEmpty);
    expect(controller.isSubmitting, isFalse);
  });

  for (final size in const [Size(390, 844), Size(800, 1280), Size(1280, 800)]) {
    testWidgets(
      'POS renders without overflow at ${size.width}x${size.height}',
      (tester) async {
        final controller = await _controller();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light,
              home: PosScreen(controller: controller, syncSummary: _sync),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('pos-search')), findsOneWidget);
        expect(find.byKey(const Key('pos-checkout')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'tapping a product twice renders one cart row with quantity two',
    (tester) async {
      final controller = await _controller();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: PosScreen(controller: controller, syncSummary: _sync),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('pos-product-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pos-product-1')));
      await tester.pump();
      expect(controller.lines, hasLength(1));
      expect(controller.lines.single.quantity, 2);
      expect(find.byKey(const Key('pos-quantity-1')), findsOneWidget);
      expect(find.byKey(const Key('pos-discount')), findsOneWidget);
    },
  );

  testWidgets('search field filters product cards while offline', (
    tester,
  ) async {
    final controller = await _controller();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: PosScreen(controller: controller, syncSummary: _sync),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('pos-search')), 'AG-1');
    await tester.pump();
    expect(find.byKey(const Key('pos-product-2')), findsOneWidget);
    expect(find.byKey(const Key('pos-product-1')), findsNothing);
    expect(find.textContaining('Sin conexión'), findsWidgets);
  });

  testWidgets('leaving with cart asks for confirmation', (tester) async {
    final controller = await _controller();
    controller.addProduct(controller.visibleProducts.first);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: PosScreen(controller: controller, syncSummary: _sync),
        ),
      ),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Descartar venta actual'), findsOneWidget);
  });
}

const _sync = SyncSummary(
  pendingCount: 0,
  retryingCount: 0,
  attentionCount: 0,
  conflictCount: 0,
  isOnline: false,
  isSyncing: false,
);

Future<PosController> _controller({
  bool cashOpen = true,
  Future<CompletedSale> Function(List<CartLine>)? onComplete,
}) async {
  final bootstrap = PosBootstrap(
    products: const [
      PosProduct(
        id: 1,
        globalId: 'coffee',
        code: 'CAF-1',
        name: 'Café americano',
        priceCents: 4500,
        stock: 3,
        categoryId: 1,
      ),
      PosProduct(
        id: 2,
        globalId: 'water',
        code: 'AG-1',
        name: 'Agua',
        priceCents: 900,
        stock: 8,
        categoryId: 2,
      ),
      PosProduct(
        id: 3,
        globalId: 'empty',
        code: 'OUT',
        name: 'Agotado',
        priceCents: 9999900,
        stock: 0,
        categoryId: 1,
      ),
    ],
    categories: const [
      PosCategory(1, 'Bebidas calientes'),
      PosCategory(2, 'Bebidas frías'),
    ],
    capabilities: EffectiveCapabilities.fromContext(
      const LocalAppContext(
        businessId: 1,
        businessGlobalId: 'b',
        branchId: 2,
        branchGlobalId: 'br',
        deviceId: 3,
        deviceGlobalId: 'd',
        deviceMode: 'PointOfSale',
        userId: 4,
        userGlobalId: 'u',
        role: 'Seller',
      ),
    ),
    branchName: 'Centro',
    userName: 'Rafael',
    cashOpen: cashOpen,
  );
  final controller = PosController(
    load: () async => bootstrap,
    completeSale:
        (
          lines, {
          required paymentMethod,
          discountCents = 0,
          receivedCents,
          authorizationGrant,
        }) =>
            onComplete?.call(lines) ??
            Future.value(
              CompletedSale(
                'sale',
                lines.fold(0, (sum, line) => sum + line.totalCents) -
                    discountCents,
                0,
              ),
            ),
  );
  await controller.initialize();
  return controller;
}
