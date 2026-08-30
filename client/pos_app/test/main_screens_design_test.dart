import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/features/cash/presentation/cash_screen.dart';
import 'package:pos_app/features/inventory/presentation/inventory_screen.dart';
import 'package:pos_app/features/products/presentation/products_screen.dart';
import 'package:pos_app/features/purchases/presentation/purchases_screen.dart';
import 'package:pos_app/features/reports/presentation/reports_screen.dart';
import 'package:pos_app/features/sales/presentation/sales_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final screens = <String, ({Widget screen, String visibleLabel})>{
    'Login': (screen: const LoginScreen(), visibleLabel: 'Bienvenido'),
    'Productos': (screen: const ProductsScreen(), visibleLabel: 'Productos'),
    'Compras': (screen: const PurchasesScreen(), visibleLabel: 'Compras'),
    'Inventario': (screen: const InventoryScreen(), visibleLabel: 'Inventario'),
    'Ventas': (screen: const SalesScreen(), visibleLabel: 'Ventas'),
    'Caja': (screen: const CashScreen(), visibleLabel: 'Caja'),
    'Reportes': (screen: const ReportsScreen(), visibleLabel: 'Reportes'),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} renders on tablet without initial overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: AppTheme.light, home: entry.value.screen)));
      await tester.pump();

      expect(find.text(entry.value.visibleLabel), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
