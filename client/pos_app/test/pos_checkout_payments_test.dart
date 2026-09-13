import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/payments/domain/sale_payment.dart';
import 'package:pos_app/features/pos/data/pos_catalog_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/presentation/pos_controller.dart';
import 'package:pos_app/features/pos/presentation/pos_screen.dart';
import 'package:pos_app/sync/sync_health.dart';

void main() {
  test('tarjeta cobra el total sin exigir efectivo recibido', () async {
    List<SalePaymentInput>? capturedPayments;
    int? capturedReceived = -1;
    final controller = await _controller(
      completeSale:
          (
            lines, {
            required payments,
            discountCents = 0,
            receivedCents,
            authorizationGrant,
          }) async {
            capturedPayments = payments;
            capturedReceived = receivedCents;
            return const CompletedSale('card-sale', 4500, 0);
          },
    );

    controller.addProduct(controller.visibleProducts.first);
    controller.setPaymentMode(PosPaymentMode.card);

    expect(controller.canCheckout, isTrue);
    expect(controller.cashPaymentCents, 0);
    expect(controller.changeCents, 0);

    final sale = await controller.submit();

    expect(sale?.globalId, 'card-sale');
    expect(capturedReceived, isNull);
    expect(capturedPayments, hasLength(1));
    expect(capturedPayments!.single.method, PaymentMethod.card);
    expect(capturedPayments!.single.amountCents, 4500);
  });

  test('transferencia cobra el total sin afectar efectivo', () async {
    List<SalePaymentInput>? capturedPayments;
    int? capturedReceived = -1;
    final controller = await _controller(
      completeSale:
          (
            lines, {
            required payments,
            discountCents = 0,
            receivedCents,
            authorizationGrant,
          }) async {
            capturedPayments = payments;
            capturedReceived = receivedCents;
            return const CompletedSale('transfer-sale', 4500, 0);
          },
    );

    controller.addProduct(controller.visibleProducts.first);
    controller.setPaymentMode(PosPaymentMode.transfer);

    expect(controller.canCheckout, isTrue);
    expect(await controller.submit(), isNotNull);
    expect(capturedReceived, isNull);
    expect(capturedPayments!.single.method, PaymentMethod.transfer);
    expect(capturedPayments!.single.amountCents, 4500);
  });

  test(
    'mixto exige suma exacta y calcula cambio sólo sobre efectivo',
    () async {
      List<SalePaymentInput>? capturedPayments;
      int? capturedReceived;
      final controller = await _controller(
        completeSale:
            (
              lines, {
              required payments,
              discountCents = 0,
              receivedCents,
              authorizationGrant,
            }) async {
              capturedPayments = payments;
              capturedReceived = receivedCents;
              return const CompletedSale('mixed-sale', 4500, 0);
            },
      );

      controller.addProduct(controller.visibleProducts.first);
      controller.setPaymentMode(PosPaymentMode.mixed);

      controller.setMixedPaymentCents(PaymentMethod.cash, 1500);
      expect(controller.canCheckout, isFalse);
      expect(controller.paymentDifferenceCents, 3000);

      controller.fillMixedRemaining(PaymentMethod.card);
      expect(controller.mixedCardCents, 3000);
      expect(controller.paymentDifferenceCents, 0);
      expect(controller.canCheckout, isFalse);

      controller.setReceivedCents(2000);
      expect(controller.canCheckout, isTrue);
      expect(controller.changeCents, 500);

      await controller.submit();

      expect(capturedReceived, 2000);
      expect(capturedPayments, hasLength(2));
      expect(
        capturedPayments!
            .where((payment) => payment.method == PaymentMethod.cash)
            .single
            .amountCents,
        1500,
      );
      expect(
        capturedPayments!
            .where((payment) => payment.method == PaymentMethod.card)
            .single
            .amountCents,
        3000,
      );
    },
  );

  test('mixto tarjeta más transferencia no pide efectivo recibido', () async {
    List<SalePaymentInput>? capturedPayments;
    int? capturedReceived = -1;
    final controller = await _controller(
      completeSale:
          (
            lines, {
            required payments,
            discountCents = 0,
            receivedCents,
            authorizationGrant,
          }) async {
            capturedPayments = payments;
            capturedReceived = receivedCents;
            return const CompletedSale('mixed-noncash', 4500, 0);
          },
    );

    controller.addProduct(controller.visibleProducts.first);
    controller.setPaymentMode(PosPaymentMode.mixed);
    controller.setMixedPaymentCents(PaymentMethod.card, 2000);
    controller.fillMixedRemaining(PaymentMethod.transfer);

    expect(controller.mixedTransferCents, 2500);
    expect(controller.cashPaymentCents, 0);
    expect(controller.canCheckout, isTrue);

    await controller.submit();

    expect(capturedReceived, isNull);
    expect(capturedPayments, hasLength(2));
    expect(capturedPayments!.map((payment) => payment.method).toSet(), {
      PaymentMethod.card,
      PaymentMethod.transfer,
    });
  });

  test('mixto bloquea método único, faltante y exceso', () async {
    final controller = await _controller();
    controller.addProduct(controller.visibleProducts.first);
    controller.setPaymentMode(PosPaymentMode.mixed);

    controller.setMixedPaymentCents(PaymentMethod.card, 4500);
    expect(controller.canCheckout, isFalse);
    expect(
      controller.checkoutBlockReason,
      contains('al menos dos formas de pago'),
    );

    controller.setMixedPaymentCents(PaymentMethod.transfer, 100);
    expect(controller.paymentDifferenceCents, -100);
    expect(controller.canCheckout, isFalse);
    expect(controller.checkoutBlockReason, contains('excede'));

    controller.setMixedPaymentCents(PaymentMethod.card, 4400);
    expect(controller.paymentDifferenceCents, 0);
    expect(controller.canCheckout, isTrue);
  });

  test(
    'importe exacto habilita efectivo y nueva venta vuelve a Cash',
    () async {
      final controller = await _controller();
      controller.addProduct(controller.visibleProducts.first);

      expect(controller.canCheckout, isFalse);
      controller.setReceivedExact();
      expect(controller.receivedCents, 4500);
      expect(controller.changeCents, 0);
      expect(controller.canCheckout, isTrue);

      controller.setPaymentMode(PosPaymentMode.card);
      expect(await controller.submit(), isNotNull);
      expect(controller.lines, isEmpty);
      expect(controller.paymentMode, PosPaymentMode.cash);
      expect(controller.receivedCents, 0);
    },
  );

  test('turno sin caja abierta bloquea también pagos no efectivo', () async {
    final controller = await _controller(cashOpen: false);
    controller.addProduct(controller.visibleProducts.first);
    controller.setPaymentMode(PosPaymentMode.card);

    expect(controller.canCheckout, isFalse);
    expect(controller.checkoutBlockReason, contains('Abre caja'));
    expect(await controller.submit(), isNull);
  });

  testWidgets('selector cambia entre tarjeta y pago mixto', (tester) async {
    final controller = await _controller();
    controller.addProduct(controller.visibleProducts.first);

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
    await tester.pump();

    expect(find.text('Efectivo recibido'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('pos-payment-card')));
    await tester.tap(find.byKey(const Key('pos-payment-card')));
    await tester.pump();

    expect(controller.paymentMode, PosPaymentMode.card);
    expect(find.text('Efectivo recibido'), findsNothing);
    expect(find.textContaining('No modifica el efectivo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pos-payment-mixed')));
    await tester.pump();

    expect(controller.paymentMode, PosPaymentMode.mixed);
    expect(
      find.byKey(ValueKey('pos-mixed-cash-${controller.paymentInputRevision}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('pos-mixed-card-${controller.paymentInputRevision}')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('pos-mixed-transfer-${controller.paymentInputRevision}'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pago mixto no desborda en viewport compacto', (tester) async {
    final controller = await _controller();
    controller.addProduct(controller.visibleProducts.first);
    controller.setPaymentMode(PosPaymentMode.mixed);
    controller.setMixedPaymentCents(PaymentMethod.cash, 1500);
    controller.fillMixedRemaining(PaymentMethod.card);
    controller.setReceivedExact();

    tester.view.physicalSize = const Size(390, 844);
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

    expect(find.byKey(const Key('pos-checkout')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  PosSaleCompleter? completeSale,
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
        categoryName: 'Bebidas',
        barcode: '750000000001',
      ),
    ],
    categories: const [PosCategory(1, 'Bebidas')],
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
        completeSale ??
        (
          lines, {
          required payments,
          discountCents = 0,
          receivedCents,
          authorizationGrant,
        }) async => CompletedSale(
          'sale',
          lines.fold<int>(0, (total, line) => total + line.totalCents) -
              discountCents,
          0,
        ),
  );

  await controller.initialize();
  return controller;
}
