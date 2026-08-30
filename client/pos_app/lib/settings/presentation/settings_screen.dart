import 'package:flutter/material.dart';
import 'package:pos_app/core/design/components/app_components.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const AppPage(
    title: 'Configuración',
    subtitle: 'Preferencias y administración del sistema.',
    body: AppCard(
      child: ListTile(
        leading: Icon(Icons.admin_panel_settings_outlined),
        title: Text('Configuración protegida'),
        subtitle: Text(
          'La configuración sensible requiere autorización de administrador.',
        ),
      ),
    ),
  );
}
