import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/navigation_model.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/sync/presentation/sync_status_panel.dart';
import 'package:pos_app/core/design/app_spacing.dart';

class AppNavigationDrawer extends ConsumerWidget {
  const AppNavigationDrawer({this.capabilities, this.currentRoute, super.key});

  final EffectiveCapabilities? capabilities;
  final String? currentRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplied = capabilities;
    if (supplied != null) {
      return _NavigationDrawer(
        capabilities: supplied,
        currentRoute: currentRoute,
        showSyncStatus: false,
      );
    }
    return ref
        .watch(effectiveCapabilitiesProvider)
        .when(
          data: (effective) => _NavigationDrawer(
            capabilities: effective,
            currentRoute: currentRoute,
            showSyncStatus: true,
          ),
          loading: () => const _NavigationDrawer(
            capabilities: EffectiveCapabilities.denied(),
            showSyncStatus: false,
          ),
          error: (_, _) => const _NavigationDrawer(
            capabilities: EffectiveCapabilities.denied(),
            showSyncStatus: false,
          ),
        );
  }
}

class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer({
    required this.capabilities,
    required this.showSyncStatus,
    this.currentRoute,
  });

  final EffectiveCapabilities capabilities;
  final String? currentRoute;
  final bool showSyncStatus;

  @override
  Widget build(BuildContext context) {
    final sections = visibleNavigationSections(capabilities);
    final route = currentRoute ?? GoRouterState.of(context).uri.path;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.storefront,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POS Flutter',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Operación comercial',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (
            var sectionIndex = 0;
            sectionIndex < sections.length;
            sectionIndex++
          ) ...[
            if (sectionIndex > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                sections[sectionIndex].title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: .7,
                ),
              ),
            ),
            for (final item in sections[sectionIndex].items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                selected:
                    route == item.route || route.startsWith('${item.route}/'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(item.route);
                },
              ),
          ],
          if (showSyncStatus) ...[const Divider(), const SyncStatusPanel()],
        ],
      ),
    );
  }
}
