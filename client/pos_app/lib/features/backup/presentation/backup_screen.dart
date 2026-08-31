import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/backup/data/local_backup_provider.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Respaldos',
    subtitle: 'Protege la información local del dispositivo.',
    primaryAction: AppPrimaryButton(
      label: 'Crear respaldo',
      icon: Icons.backup_outlined,
      onPressed: _busy ? null : _create,
    ),
    body: AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Respaldo local'),
            subtitle: Text(
              'Guarda una copia recuperable de la base de datos de este dispositivo.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restaurar respaldo'),
            subtitle: const Text(
              'Reemplaza los datos locales. Requiere confirmación y autorización.',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: _busy ? null : _restore,
          ),
        ],
      ),
    ),
  );

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final path = await LocalBackupProvider(appDatabase).createBackup();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Respaldo creado en $path')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fue posible crear el respaldo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final values = await configuredTextForm(context, 'Restaurar respaldo', [
      const TextFormFieldSpec(
        'Ruta del archivo',
        helperText: 'Selecciona una copia .db creada por esta aplicación.',
      ),
    ]);
    if (values == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AppDialog(
            title: 'Confirmar restauración',
            content: const Text(
              'Esta acción reemplazará los datos locales actuales. Se creará una copia preventiva antes de continuar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              AppPrimaryButton(
                label: 'Restaurar datos',
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await runWithSpecialAuthorization(
        context: context,
        capability: Capability.backupRestore,
        operationLabel: 'Restaurar respaldo',
        reason: 'Restauración destructiva confirmada por el usuario',
        operation:
            (grant) => LocalBackupProvider(appDatabase).restoreBackup(
              values.first,
              reauthenticationGrant: grant,
              confirmedDestructiveRestore: true,
            ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Respaldo restaurado correctamente.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible restaurar el respaldo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
