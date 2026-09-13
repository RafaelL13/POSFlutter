import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/navigation_model.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/auth/data/auth_repository.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/sync/presentation/sync_status_panel.dart';
import 'package:pos_app/core/design/app_spacing.dart';

class AppNavigationDrawer extends ConsumerWidget {
  const AppNavigationDrawer({
    this.capabilities,
    this.currentRoute,
    this.onLogout,
    super.key,
  });

  final EffectiveCapabilities? capabilities;
  final String? currentRoute;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logout =
        onLogout ??
        () async {
          await AuthRepository(appDatabase).logout();
          ref.invalidate(effectiveCapabilitiesProvider);
        };
    final supplied = capabilities;
    if (supplied != null) {
      return _NavigationDrawer(
        capabilities: supplied,
        currentRoute: currentRoute,
        showSyncStatus: false,
        onLogout: logout,
      );
    }
    return ref
        .watch(effectiveCapabilitiesProvider)
        .when(
          data: (effective) => _NavigationDrawer(
            capabilities: effective,
            currentRoute: currentRoute,
            showSyncStatus: true,
            onLogout: logout,
          ),
          loading: () => _NavigationDrawer(
            capabilities: EffectiveCapabilities.denied(),
            showSyncStatus: false,
            onLogout: logout,
          ),
          error: (_, _) => _NavigationDrawer(
            capabilities: EffectiveCapabilities.denied(),
            showSyncStatus: false,
            onLogout: logout,
          ),
        );
  }
}

class _NavigationDrawer extends StatefulWidget {
  const _NavigationDrawer({
    required this.capabilities,
    required this.showSyncStatus,
    required this.onLogout,
    this.currentRoute,
  });

  final EffectiveCapabilities capabilities;
  final String? currentRoute;
  final bool showSyncStatus;
  final Future<void> Function() onLogout;

  @override
  State<_NavigationDrawer> createState() => _NavigationDrawerState();
}

class _NavigationDrawerState extends State<_NavigationDrawer> {
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) {
    final sections = visibleNavigationSections(widget.capabilities);
    final route = widget.currentRoute ?? GoRouterState.of(context).uri.path;
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
                Expanded(
                  child: Column(
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
          if (widget.showSyncStatus) ...[
            const Divider(),
            const SyncStatusPanel(),
          ],
          const Divider(),
          ListTile(
            key: const Key('logout-tile'),
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            enabled: !_loggingOut,
            onTap: _loggingOut
                ? null
                : () async {
                    var confirming = false;
                    final confirmed =
                        await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => StatefulBuilder(
                            builder: (dialogContext, setDialogState) =>
                                AlertDialog(
                                  title: const Text('Cerrar sesión'),
                                  content: const Text(
                                    '¿Deseas cerrar la sesión actual en este dispositivo?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: confirming
                                          ? null
                                          : () => Navigator.pop(
                                              dialogContext,
                                              false,
                                            ),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: confirming
                                          ? null
                                          : () {
                                              if (confirming) return;
                                              confirming = true;
                                              setDialogState(() {});
                                              Navigator.pop(
                                                dialogContext,
                                                true,
                                              );
                                            },
                                      child: const Text('Cerrar sesión'),
                                    ),
                                  ],
                                ),
                          ),
                        ) ??
                        false;

                    if (!confirmed || !context.mounted) return;

                    setState(() => _loggingOut = true);
                    await widget.onLogout();

                    if (!context.mounted) return;

                    context.go('/login');
                  },
          ),
        ],
      ),
    );
  }
}
