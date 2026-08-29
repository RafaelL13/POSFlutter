import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/navigation_model.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';

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
      );
    }
    return ref
        .watch(effectiveCapabilitiesProvider)
        .when(
          data: (effective) => _NavigationDrawer(
            capabilities: effective,
            currentRoute: currentRoute,
          ),
          loading: () => const _NavigationDrawer(
            capabilities: EffectiveCapabilities.denied(),
          ),
          error: (_, _) => const _NavigationDrawer(
            capabilities: EffectiveCapabilities.denied(),
          ),
        );
  }
}

class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer({required this.capabilities, this.currentRoute});

  final EffectiveCapabilities capabilities;
  final String? currentRoute;

  @override
  Widget build(BuildContext context) {
    final sections = visibleNavigationSections(capabilities);
    final route = currentRoute ?? GoRouterState.of(context).uri.path;
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(child: Text('POS Flutter')),
          for (
            var sectionIndex = 0;
            sectionIndex < sections.length;
            sectionIndex++
          ) ...[
            if (sectionIndex > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                sections[sectionIndex].title,
                style: Theme.of(context).textTheme.labelMedium,
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
        ],
      ),
    );
  }
}
