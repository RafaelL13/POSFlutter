import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/sync/sync_error.dart';
import 'package:pos_app/sync/sync_health.dart';
import 'package:pos_app/sync/sync_repository.dart';

typedef ConnectivityLoader = Future<List<ConnectivityResult>> Function();

final class SyncStatusController {
  SyncStatusController(this._repository, {ConnectivityLoader? connectivity})
    : _connectivity =
          connectivity ?? (() => Connectivity().checkConnectivity());

  final SyncRepository _repository;
  final ConnectivityLoader _connectivity;

  Future<SyncSummary> load() async {
    final connectivity = await _connectivity();
    final online = connectivity.any((item) => item != ConnectivityResult.none);
    return _repository.summary(isOnline: online);
  }

  Future<List<SyncAttentionItem>> attentionItems() =>
      _repository.attentionItems();
}

class SyncStatusPanel extends StatefulWidget {
  const SyncStatusPanel({this.controller, this.summary, super.key});

  final SyncStatusController? controller;
  final SyncSummary? summary;

  @override
  State<SyncStatusPanel> createState() => _SyncStatusPanelState();
}

class _SyncStatusPanelState extends State<SyncStatusPanel> {
  late final SyncStatusController _controller =
      widget.controller ?? SyncStatusController(localSyncRepository);
  Future<SyncSummary>? _summary;

  @override
  void initState() {
    super.initState();
    if (widget.summary == null) _summary = _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final supplied = widget.summary;
    if (supplied != null) return _body(context, supplied);
    return FutureBuilder<SyncSummary>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Estado de sincronización no disponible'),
          );
        }
        final summary = snapshot.data;
        if (summary == null) {
          return const ListTile(
            leading: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Consultando sincronización...'),
          );
        }
        return _body(context, summary);
      },
    );
  }

  Widget _body(BuildContext context, SyncSummary summary) => ListTile(
    leading: Icon(_icon(summary)),
    title: Text(summary.headline),
    subtitle: _details(summary),
    onTap:
        (summary.attentionCount > 0 ||
                summary.pullFailure?.requiresAction == true) &&
            widget.summary == null
        ? () => _showAttention(context, summary.pullFailure)
        : null,
  );

  Widget? _details(SyncSummary summary) {
    final labels = <String>[
      if (summary.pendingCount > 0) 'Pendientes: ${summary.pendingCount}',
      if (summary.retryingCount > 0) 'Reintentando: ${summary.retryingCount}',
      if (summary.attentionCount > 0)
        'Requiere atención: ${summary.attentionCount}',
      if (summary.conflictCount > 0) 'Conflictos: ${summary.conflictCount}',
    ];
    return labels.isEmpty ? null : Text(labels.join(' · '));
  }

  IconData _icon(SyncSummary summary) {
    if (!summary.isOnline) return Icons.cloud_off_outlined;
    if (summary.isSyncing) return Icons.sync;
    if (summary.attentionCount > 0 || summary.conflictCount > 0) {
      return Icons.warning_amber_rounded;
    }
    if (summary.pendingCount > 0 || summary.retryingCount > 0) {
      return Icons.cloud_upload_outlined;
    }
    return Icons.cloud_done_outlined;
  }

  Future<void> _showAttention(
    BuildContext context,
    SyncFailure? pullFailure,
  ) async {
    final items = await _controller.attentionItems();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Operaciones que requieren atención'),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length + (pullFailure == null ? 0 : 1),
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, index) {
              if (pullFailure != null && index == 0) {
                return ListTile(
                  title: const Text('Sincronización remota'),
                  subtitle: Text(
                    '${pullFailure.message}\n${_pullAction(pullFailure)}',
                  ),
                  isThreeLine: true,
                );
              }
              final itemIndex = index - (pullFailure == null ? 0 : 1);
              final item = items[itemIndex];
              return ListTile(
                title: Text(item.entityLabel),
                subtitle: Text('${item.message}\n${item.recommendedAction}'),
                isThreeLine: true,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _pullAction(SyncFailure failure) => switch (failure.category) {
    SyncErrorCategory.authenticationRequired => 'Volver a autenticar',
    SyncErrorCategory.authorizationRejected => 'Solicitar revisión',
    SyncErrorCategory.validationRejected => 'Revisar la sincronización',
    SyncErrorCategory.conflict => 'Resolver conflicto',
    SyncErrorCategory.unsupportedOperation =>
      'Actualizar o contactar al administrador',
    SyncErrorCategory.networkError ||
    SyncErrorCategory.serverError => 'No se requiere acción',
  };
}
