import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/sales/presentation/sales_screen.dart';

void main() {
  testWidgets(
    'cancellation reloads sales without an async setState exception',
    (tester) async {
      var cancelled = false;
      var loadCount = 0;
      var cancellationCount = 0;

      Future<List<Map<String, Object?>>> loadSales() async {
        loadCount++;
        return [
          <String, Object?>{
            'global_id': 'sale-uat-1',
            'folio': 'V-UAT-1',
            'sale_datetime': '2026-09-13T21:38:00Z',
            'total_cents': 12500,
            'status': cancelled ? 'Cancelled' : 'Confirmed',
          },
        ];
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SalesScreen(
            loader: loadSales,
            cancellationRunner: (_, sale, reason) async {
              cancellationCount++;
              expect(sale['global_id'], 'sale-uat-1');
              expect(reason, 'Prueba UAT');
              cancelled = true;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmed'), findsOneWidget);
      await tester.tap(find.text('Cancelar venta'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownButtonFormField<Map<String, Object?>>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Folio V-UAT-1').last);
      await tester.enterText(
        find.widgetWithText(TextField, 'Motivo *'),
        'Prueba UAT',
      );
      await tester.tap(find.text('Continuar autorización'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      expect(cancellationCount, 1);
      expect(loadCount, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
