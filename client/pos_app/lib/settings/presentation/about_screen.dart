import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/branding/presentation/branding_providers.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = resolvedBranding(ref.watch(businessBrandingProvider));
    return AppPage(
      title: 'Acerca de',
      subtitle: branding.displayName,
      body: AppCard(
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (_, snapshot) {
            final info = snapshot.data;
            return Column(
              children: [
                _row(
                  'Versión',
                  info == null
                      ? 'Cargando…'
                      : '${info.version} (${info.buildNumber})',
                ),
                _row('Sucursal', branding.branchName ?? 'No configurada'),
                _row('Dispositivo', branding.deviceName ?? 'No configurado'),
                _row('Modo', branding.deviceMode ?? 'No disponible'),
                _row('Base local', 'Esquema ${AppDatabase.schemaVersion}'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value) => ListTile(
    title: Text(label),
    trailing: Text(value, textAlign: TextAlign.end),
  );
}
