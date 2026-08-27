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

final appRouter = GoRouter(initialLocation:'/first-run',routes:[
  GoRoute(path:'/first-run',builder:(_,__)=>const FirstRunScreen()),
  GoRoute(path:'/login',builder:(_,__)=>const LoginScreen()),
  GoRoute(path:'/dashboard',builder:(_,__)=>const DashboardScreen()),
  GoRoute(path:'/pos',builder:(_,__)=>const PosScreen()),
  GoRoute(path:'/products',builder:(_,__)=>const ProductsScreen()),
  GoRoute(path:'/categories',builder:(_,__)=>const CategoriesScreen()),
  GoRoute(path:'/suppliers',builder:(_,__)=>const SuppliersScreen()),
  GoRoute(path:'/purchases',builder:(_,__)=>const PurchasesScreen()),
  GoRoute(path:'/inventory',builder:(_,__)=>const InventoryScreen()),
  GoRoute(path:'/sales',builder:(_,__)=>const SalesScreen()),
  GoRoute(path:'/cash',builder:(_,__)=>const CashScreen()),
  GoRoute(path:'/expenses',builder:(_,__)=>const ExpensesScreen()),
  GoRoute(path:'/reports',builder:(_,__)=>const ReportsScreen()),
  GoRoute(path:'/users',builder:(_,__)=>const UsersScreen()),
  GoRoute(path:'/backup',builder:(_,__)=>const BackupScreen()),
  GoRoute(path:'/cloud-admin',builder:(_,__)=>const CloudAdminScreen()),
  GoRoute(path:'/cloud-admin/reports',builder:(_,__)=>const RemoteReportsScreen()),
  GoRoute(path:'/cloud-admin/reports/:kind',builder:(_,state){final name=state.pathParameters['kind'];RemoteReportKind? kind;for(final candidate in RemoteReportKind.values){if(candidate.name==name){kind=candidate;break;}}return kind==null?const RemoteReportsScreen():RemoteReportDetailScreen(kind:kind);}),
]);
