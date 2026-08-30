import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/dashboard/data/home_repository.dart';
import 'package:pos_app/features/dashboard/presentation/home_content.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';
import 'package:pos_app/sync/sync_health.dart';

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
    appBar: AppBar(title: const Text('Inicio')),
    drawer: summary == null
        ? const AppNavigationDrawer()
        : AppNavigationDrawer(
            capabilities: summary!.capabilities,
            currentRoute: '/dashboard',
          ),
    body: summary != null
        ? HomeContent(summary: summary!, syncSummary: syncSummary)
        : FutureBuilder<HomeSummary>(
            future: (loader ?? HomeRepository(appDatabase).load)(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const _HomeLoadError();
              final value = snapshot.data;
              if (value == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return HomeContent(summary: value, syncSummary: syncSummary);
            },
          ),
  );
}

class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_work_outlined, size: 44),
          SizedBox(height: 12),
          Text('No fue posible cargar el resumen local.'),
          SizedBox(height: 4),
          Text('Puedes seguir usando las opciones disponibles en el menú.'),
        ],
      ),
    ),
  );
}
