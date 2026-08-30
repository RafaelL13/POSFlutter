import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/backup/data/local_backup_provider.dart';

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Respaldos',
    subtitle: 'Protege la información local del dispositivo.',
    primaryAction: AppPrimaryButton(
      label: 'Crear respaldo',
      icon: Icons.backup_outlined,
      onPressed: () async {
        final path = await LocalBackupProvider(appDatabase).createBackup();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Respaldo creado en $path')));
        }
      },
    ),
    body: const AppCard(
      child: ListTile(
        leading: Icon(Icons.shield_outlined),
        title: Text('Respaldo local'),
        subtitle: Text(
          'Guarda una copia recuperable de la base de datos de este dispositivo.',
        ),
      ),
    ),
  );
}
