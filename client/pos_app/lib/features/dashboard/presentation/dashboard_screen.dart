import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/dashboard/data/home_repository.dart';
import 'package:pos_app/features/dashboard/presentation/home_content.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';
import 'package:pos_app/sync/sync_health.dart';
import 'package:pos_app/core/design/components/app_components.dart';

typedef HomeSummaryLoader = Future<HomeSummary> Function();

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    this.summary,
    this.loader,
    this.syncSummary,
    super.key,
  });

  final HomeSummary? summary;
  final HomeSummaryLoader? loader;
  final SyncSummary? syncSummary;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('POS Flutter')),
    drawer: summary == null
        ? const AppNavigationDrawer()
        : AppNavigationDrawer(
            capabilities: summary!.capabilities,
            currentRoute: '/dashboard',
          ),
    body: SafeArea(
      child: summary != null
          ? HomeContent(summary: summary!, syncSummary: syncSummary)
          : FutureBuilder<HomeSummary>(
              future: (loader ?? HomeRepository(appDatabase).load)(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const AppErrorState(
                    message: 'No fue posible cargar el resumen local. Puedes seguir usando las opciones disponibles en el menú.',
                  );
                }
                final value = snapshot.data;
                if (value == null) {
                  return const AppLoadingState(label: 'Preparando tu inicio…');
                }
                return HomeContent(summary: value, syncSummary: syncSummary);
              },
            ),
    ),
  );
}
