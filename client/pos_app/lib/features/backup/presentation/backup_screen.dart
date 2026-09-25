import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/backup/data/local_backup_provider.dart';
import 'package:pos_app/features/backup/presentation/backup_file_transport.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.fileTransport});

  final BackupFileTransport? fileTransport;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  BackupFileTransport get _fileTransport =>
      widget.fileTransport ?? BackupFileTransport();

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Respaldos',
    subtitle: 'Protege la información local del dispositivo.',
    primaryAction: AppPrimaryButton(
      label: 'Crear y guardar respaldo',
      icon: Icons.backup_outlined,
      onPressed: _busy ? null : _create,
    ),
    body: AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Respaldo recuperable'),
            subtitle: Text(
              'Crea una copia íntegra y permite guardarla fuera de la aplicación.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restaurar respaldo'),
            subtitle: const Text(
              'Selecciona un archivo .db. Requiere confirmación y autorización.',
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
      final internalPath = await LocalBackupProvider(appDatabase)
          .createBackup();

      final exported = await _fileTransport.exportBackup(internalPath);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            exported
                ? 'Respaldo guardado correctamente.'
                : 'El respaldo fue creado, pero no se exportó. '
                      'Selecciona Crear y guardar respaldo para intentarlo de nuevo.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible crear o guardar el respaldo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    StagedBackupFile? stagedBackup;

    try {
      stagedBackup = await _fileTransport.pickAndStageRestore();

      if (stagedBackup == null || !mounted) return;

      setState(() => _busy = true);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Confirmar restauración',
          content: Text(
            'Se restaurará "${stagedBackup!.originalName}".\n\n'
            'Esta acción reemplazará los datos locales actuales. '
            'Se creará una copia preventiva antes de continuar.',
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

      await runWithSpecialAuthorization(
        context: context,
        capability: Capability.backupRestore,
        operationLabel: 'Restaurar respaldo',
        reason: 'Restauración destructiva confirmada por el usuario',
        operation: (grant) => LocalBackupProvider(appDatabase).restoreBackup(
          stagedBackup!.file.path,
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
      await stagedBackup?.delete();

      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }
}
