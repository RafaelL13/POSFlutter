import 'package:pos_app/sync/sync_error.dart';

final class SyncSummary {
  const SyncSummary({
    required this.pendingCount,
    required this.retryingCount,
    required this.attentionCount,
    required this.conflictCount,
    required this.isOnline,
    required this.isSyncing,
    this.pullFailure,
  });

  final int pendingCount;
  final int retryingCount;
  final int attentionCount;
  final int conflictCount;
  final bool isOnline;
  final bool isSyncing;
  final SyncFailure? pullFailure;

  int get unsyncedCount => pendingCount + retryingCount + attentionCount;

  String get headline {
    if (!isOnline) {
      return 'Sin conexión — $unsyncedCount cambios pendientes';
    }
    if (isSyncing) return 'Sincronizando...';
    if (conflictCount > 0) return '$conflictCount conflictos pendientes';
    if (attentionCount > 0 || pullFailure?.requiresAction == true) {
      final count =
          attentionCount + (pullFailure?.requiresAction == true ? 1 : 0);
      return '$count operaciones requieren atención';
    }
    if (pendingCount > 0 || retryingCount > 0) {
      return '${pendingCount + retryingCount} cambios pendientes';
    }
    return 'Sincronizado';
  }
}

final class SyncAttentionItem {
  const SyncAttentionItem({
    required this.entityLabel,
    required this.createdAt,
    required this.category,
    required this.message,
    required this.recommendedAction,
  });

  final String entityLabel;
  final DateTime createdAt;
  final SyncErrorCategory category;
  final String message;
  final String recommendedAction;

  factory SyncAttentionItem.fromRow(Map<String, Object?> row) {
    final category = SyncErrorCategory.tryParse(
      row['error_category'] as String?,
    )!;
    return SyncAttentionItem(
      entityLabel: _entityLabel(row['entity_type'] as String),
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      category: category,
      message: _message(category),
      recommendedAction: _action(category),
    );
  }

  static String _entityLabel(String value) => switch (value) {
    'Sale' => 'Venta',
    'Purchase' => 'Compra',
    'InventoryAdjustment' => 'Ajuste de inventario',
    'CashSession' => 'Caja',
    'Product' => 'Producto',
    'Category' => 'Categoría',
    'Supplier' => 'Proveedor',
    _ => 'Operación local',
  };

  static String _message(SyncErrorCategory category) => switch (category) {
    SyncErrorCategory.authenticationRequired =>
      'Se necesita iniciar sesión nuevamente.',
    SyncErrorCategory.authorizationRejected =>
      'La operación ya no está autorizada para sincronizarse.',
    SyncErrorCategory.validationRejected =>
      'La operación fue rechazada y requiere revisión.',
    SyncErrorCategory.conflict => 'Existe un conflicto con la versión remota.',
    SyncErrorCategory.unsupportedOperation =>
      'La operación requiere actualización o revisión del sistema.',
    SyncErrorCategory.networkError => 'El cambio espera conexión.',
    SyncErrorCategory.serverError =>
      'El cambio se reintentará automáticamente.',
  };

  static String _action(SyncErrorCategory category) => switch (category) {
    SyncErrorCategory.authenticationRequired => 'Volver a autenticar',
    SyncErrorCategory.authorizationRejected => 'Solicitar revisión',
    SyncErrorCategory.validationRejected => 'Revisar operación',
    SyncErrorCategory.conflict => 'Resolver conflicto',
    SyncErrorCategory.unsupportedOperation =>
      'Actualizar o contactar al administrador',
    SyncErrorCategory.networkError ||
    SyncErrorCategory.serverError => 'No se requiere acción',
  };
}
