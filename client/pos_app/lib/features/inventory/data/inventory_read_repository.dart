import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';

enum CentralTransferHistoryStatus {
  pendingAck,
  syncing,
  retrying,
  attentionRequired,
  confirmed,
  localOnly,
}

final class CentralTransferHistoryItem {
  const CentralTransferHistoryItem({
    required this.transferGlobalId,
    required this.transferDate,
    required this.productCount,
    required this.totalQuantity,
    required this.status,
    required this.retryCount,
    this.appliedAt,
    this.errorCategory,
    this.nextAttemptAt,
  });

  final String transferGlobalId;
  final DateTime transferDate;
  final int productCount;
  final int totalQuantity;
  final CentralTransferHistoryStatus status;
  final int retryCount;
  final DateTime? appliedAt;
  final String? errorCategory;
  final DateTime? nextAttemptAt;
}

final class InventoryReadRepository {
  InventoryReadRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, Object?>>> availability() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryAvailabilityRead);
    final context = authorization.context!;
    final database = await _db.open();
    final costProjection = authorization.can(Capability.viewInventoryValue)
        ? ', COALESCE(SUM(l.available_quantity * l.unit_cost_cents), 0) AS value_cents'
        : '';
    return database.rawQuery(
      '''SELECT p.id, p.name, p.code, p.minimum_stock, COALESCE(SUM(l.available_quantity), 0) AS stock
         $costProjection,
         (SELECT MAX(m.movement_date) FROM inventory_movements m
          WHERE m.product_id=p.id AND m.branch_id=?) AS last_movement
         FROM products p LEFT JOIN inventory_lots l
           ON l.product_id = p.id AND l.branch_id = ? AND l.active = 1
         WHERE p.business_id = ? GROUP BY p.id, p.name, p.code, p.minimum_stock ORDER BY p.name''',
      [context.branchId, context.branchId, context.businessId],
    );
  }

  Future<List<Map<String, Object?>>> lots({int? productId}) async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryLotsRead);
    final context = authorization.context!;
    final columns = <String>[
      'id',
      'global_id',
      'product_id',
      'entry_date',
      'initial_quantity',
      'available_quantity',
      'active',
    ];
    if (authorization.can(Capability.viewFifoHistoricalCost)) {
      columns.add('unit_cost_cents');
    }
    final database = await _db.open();
    return database.query(
      'inventory_lots',
      columns: columns,
      where: 'branch_id = ?${productId == null ? '' : ' AND product_id = ?'}',
      whereArgs: [context.branchId, ?productId],
      orderBy: 'entry_date, id',
    );
  }

  Future<List<CentralTransferHistoryItem>> centralTransferHistory({
    int limit = 50,
  }) async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryAvailabilityRead);
    final context = authorization.context!;
    final database = await _db.open();
    final safeLimit = limit.clamp(1, 200);

    final movementRows = await database.rawQuery(
      '''
      SELECT
        reference_global_id AS transfer_global_id,
        MIN(movement_date) AS transfer_date,
        COUNT(DISTINCT product_id) AS product_count,
        SUM(quantity_delta) AS total_quantity
      FROM inventory_movements
      WHERE branch_id = ?
        AND type = 'CentralTransferIn'
        AND reference_global_id IS NOT NULL
      GROUP BY reference_global_id
      ORDER BY transfer_date DESC, transfer_global_id DESC
      LIMIT ?
      ''',
      [context.branchId, safeLimit],
    );

    if (movementRows.isEmpty) {
      return const <CentralTransferHistoryItem>[];
    }

    final ackRows = await database.query(
      'sync_queue',
      columns: [
        'id',
        'status',
        'payload_json',
        'retry_count',
        'error_category',
        'requires_action',
        'next_attempt_at',
      ],
      where: 'entity_type = ?',
      whereArgs: ['CentralTransferApplied'],
      orderBy: 'id DESC',
    );

    final ackByTransfer = <String, Map<String, Object?>>{};

    for (final row in ackRows) {
      final payload = _decodeCentralTransferAck(row['payload_json'] as String);

      final transferGlobalId = payload['transferGlobalId'];

      if (transferGlobalId is! String || transferGlobalId.trim().isEmpty) {
        throw StateError('CentralTransferApplied sin transferGlobalId válido.');
      }

      ackByTransfer.putIfAbsent(transferGlobalId, () => row);
    }

    return movementRows
        .map((row) {
          final transferGlobalId = row['transfer_global_id'] as String;

          final ack = ackByTransfer[transferGlobalId];
          final ackPayload = ack == null
              ? null
              : _decodeCentralTransferAck(ack['payload_json'] as String);

          return CentralTransferHistoryItem(
            transferGlobalId: transferGlobalId,
            transferDate: DateTime.parse(row['transfer_date'] as String)
                .toUtc(),
            productCount: row['product_count'] as int,
            totalQuantity: row['total_quantity'] as int,
            status: _centralTransferHistoryStatus(ack),
            retryCount: ack?['retry_count'] as int? ?? 0,
            appliedAt: _optionalUtcDate(
              ackPayload?['appliedAt'],
              field: 'appliedAt',
            ),
            errorCategory: ack?['error_category'] as String?,
            nextAttemptAt: _optionalUtcDate(
              ack?['next_attempt_at'],
              field: 'next_attempt_at',
            ),
          );
        })
        .toList(growable: false);
  }

  static Map<String, Object?> _decodeCentralTransferAck(String payloadJson) {
    final decoded = jsonDecode(payloadJson);

    if (decoded is! Map) {
      throw StateError('Payload CentralTransferApplied inválido.');
    }

    return Map<String, Object?>.from(decoded);
  }

  static CentralTransferHistoryStatus _centralTransferHistoryStatus(
    Map<String, Object?>? ack,
  ) {
    if (ack == null) {
      return CentralTransferHistoryStatus.localOnly;
    }

    final status = ack['status'];

    return switch (status) {
      'Pending' => CentralTransferHistoryStatus.pendingAck,
      'Syncing' => CentralTransferHistoryStatus.syncing,
      'Synced' => CentralTransferHistoryStatus.confirmed,
      'Error' =>
        (ack['requires_action'] as int? ?? 0) == 1 ||
                ack['next_attempt_at'] == null
            ? CentralTransferHistoryStatus.attentionRequired
            : CentralTransferHistoryStatus.retrying,
      _ => throw StateError(
        'Estado CentralTransferApplied no soportado: $status.',
      ),
    };
  }

  static DateTime? _optionalUtcDate(Object? value, {required String field}) {
    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw StateError('$field de CentralTransferApplied es inválido.');
    }

    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      throw StateError('$field de CentralTransferApplied es inválido.');
    }

    return parsed.toUtc();
  }

  Future<int> inventoryValueCents() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.viewInventoryValue);
    final context = authorization.context!;
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT COALESCE(SUM(available_quantity * unit_cost_cents), 0) AS value
         FROM inventory_lots WHERE branch_id = ? AND active = 1''',
      [context.branchId],
    );
    return rows.single['value']! as int;
  }

  Future<int> totalAvailableUnits() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryAvailabilityRead);
    final context = authorization.context!;
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT COALESCE(SUM(available_quantity), 0) AS units
         FROM inventory_lots WHERE branch_id = ? AND active = 1''',
      [context.branchId],
    );
    return rows.single['units']! as int;
  }
}
