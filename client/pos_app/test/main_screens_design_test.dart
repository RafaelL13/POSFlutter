import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/features/cash/presentation/cash_screen.dart';
import 'package:pos_app/features/backup/presentation/backup_screen.dart';
import 'package:pos_app/features/expenses/presentation/expenses_screen.dart';
import 'package:pos_app/features/inventory/presentation/inventory_screen.dart';
import 'package:pos_app/features/products/presentation/products_screen.dart';
import 'package:pos_app/features/purchases/presentation/purchases_screen.dart';
import 'package:pos_app/features/reports/presentation/reports_screen.dart';
import 'package:pos_app/features/sales/presentation/sales_screen.dart';
import 'package:pos_app/features/users/presentation/users_screen.dart';
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
    'Gastos': (screen: const ExpensesScreen(), visibleLabel: 'Gastos'),
    'Reportes': (screen: const ReportsScreen(), visibleLabel: 'Reportes'),
    'Usuarios': (screen: const UsersScreen(), visibleLabel: 'Usuarios'),
    'Respaldos': (screen: const BackupScreen(), visibleLabel: 'Respaldos'),
  };

  const viewports = <Size>[Size(390, 844), Size(800, 1280), Size(1280, 800)];

  for (final entry in screens.entries) {
    for (final viewport in viewports) {
      for (final textScale in [1.0, 1.2]) {
        testWidgets(
          '${entry.key} renders at ${viewport.width}x${viewport.height} text $textScale',
          (tester) async {
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: AppTheme.light,
                  builder:
                      (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(textScale)),
                        child: child!,
                      ),
                  home: entry.value.screen,
                ),
              ),
            );
            await tester.pump();

            expect(find.text(entry.value.visibleLabel), findsWidgets);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
