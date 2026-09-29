import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/features/inventory/presentation/inventory_screen.dart';

void main() {
  testWidgets(
    'central transfer history dialog presents confirmed retrying and local states',
    (tester) async {
      final items = [
        CentralTransferHistoryItem(
          transferGlobalId: 'transfer-confirmed',
          transferDate: DateTime.utc(2026, 9, 29, 12),
          productCount: 2,
          totalQuantity: 9,
          status: CentralTransferHistoryStatus.confirmed,
          retryCount: 0,
          appliedAt: DateTime.utc(2026, 9, 29, 12, 1),
        ),
        CentralTransferHistoryItem(
          transferGlobalId: 'transfer-retrying',
          transferDate: DateTime.utc(2026, 9, 29, 11),
          productCount: 1,
          totalQuantity: 3,
          status: CentralTransferHistoryStatus.retrying,
          retryCount: 2,
          errorCategory: 'NETWORK_ERROR',
          nextAttemptAt: DateTime.utc(2026, 9, 29, 11, 5),
        ),
        CentralTransferHistoryItem(
          transferGlobalId: 'transfer-local',
          transferDate: DateTime.utc(2026, 9, 29, 10),
          productCount: 1,
          totalQuantity: 5,
          status: CentralTransferHistoryStatus.localOnly,
          retryCount: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CentralTransferHistoryDialog(loader: () async => items),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Transferencias recibidas'), findsOneWidget);
      expect(find.text('Confirmada'), findsOneWidget);
      expect(find.text('Reintentando'), findsOneWidget);
      expect(find.text('Aplicada localmente'), findsOneWidget);
      expect(find.text('2 productos'), findsOneWidget);
      expect(find.text('9 unidades'), findsOneWidget);
      expect(find.text('Reintentos: 2'), findsOneWidget);
      expect(find.text('Sincronización: NETWORK_ERROR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('central transfer history dialog has an explicit empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CentralTransferHistoryDialog(
            loader: () async => const <CentralTransferHistoryItem>[],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('No hay transferencias centrales recibidas en esta sucursal.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
