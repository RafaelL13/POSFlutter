import 'package:go_router/go_router.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/features/backup/presentation/backup_screen.dart';
import 'package:pos_app/features/cash/presentation/cash_screen.dart';
import 'package:pos_app/features/categories/presentation/categories_screen.dart';
import 'package:pos_app/features/cloud_admin/presentation/cloud_admin_screen.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_repository.dart';
import 'package:pos_app/features/cloud_admin/reports/presentation/remote_report_detail_screen.dart';
import 'package:pos_app/features/cloud_admin/reports/presentation/remote_reports_screen.dart';
import 'package:pos_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:pos_app/features/expenses/presentation/expenses_screen.dart';
import 'package:pos_app/features/first_run/presentation/first_run_screen.dart';
import 'package:pos_app/features/inventory/presentation/inventory_screen.dart';
import 'package:pos_app/features/pos/presentation/pos_screen.dart';
import 'package:pos_app/features/products/presentation/products_screen.dart';
import 'package:pos_app/features/purchases/presentation/purchases_screen.dart';
import 'package:pos_app/features/reports/presentation/reports_screen.dart';
import 'package:pos_app/features/sales/presentation/sales_screen.dart';
import 'package:pos_app/features/suppliers/presentation/suppliers_screen.dart';
import 'package:pos_app/features/users/presentation/users_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/first-run',
  routes: [
    GoRoute(path: '/first-run', builder: (_, _) => const FirstRunScreen()),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
    GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
    GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
    GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
    GoRoute(path: '/suppliers', builder: (_, _) => const SuppliersScreen()),
    GoRoute(path: '/purchases', builder: (_, _) => const PurchasesScreen()),
    GoRoute(path: '/inventory', builder: (_, _) => const InventoryScreen()),
    GoRoute(path: '/sales', builder: (_, _) => const SalesScreen()),
    GoRoute(path: '/cash', builder: (_, _) => const CashScreen()),
    GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
    GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
    GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
    GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
    GoRoute(path: '/cloud-admin', builder: (_, _) => const CloudAdminScreen()),
    GoRoute(
      path: '/cloud-admin/reports',
      builder: (_, _) => const RemoteReportsScreen(),
    ),
    GoRoute(
      path: '/cloud-admin/reports/:kind',
      builder: (_, state) {
        final name = state.pathParameters['kind'];
        RemoteReportKind? kind;
        for (final candidate in RemoteReportKind.values) {
          if (candidate.name == name) {
            kind = candidate;
            break;
          }
        }
        return kind == null
            ? const RemoteReportsScreen()
            : RemoteReportDetailScreen(kind: kind);
      },
    ),
  ],
);
