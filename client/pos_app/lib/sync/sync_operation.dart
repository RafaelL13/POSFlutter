import 'dart:convert';

final class SyncOperationRecord {
  const SyncOperationRecord({
    required this.id,
    required this.globalId,
    required this.entityType,
    required this.entityGlobalId,
    required this.operation,
    required this.payloadVersion,
    required this.payload,
    required this.retryCount,
  });
  final int id;
  final String globalId;
  final String entityType;
  final String entityGlobalId;
  final String operation;
  final int payloadVersion;
  final Map<String, Object?> payload;
  final int retryCount;
  factory SyncOperationRecord.fromRow(Map<String, Object?> r) =>
      SyncOperationRecord(
        id: r['id'] as int,
        globalId: r['global_id'] as String,
        entityType: r['entity_type'] as String,
        entityGlobalId: r['entity_global_id'] as String,
        operation: r['operation'] as String,
        payloadVersion: r['payload_version'] as int,
        payload: Map<String, Object?>.from(
          jsonDecode(r['payload_json'] as String) as Map,
        ),
        retryCount: r['retry_count'] as int,
      );
  Map<String, Object?> toJson() => {
    'globalId': globalId,
    'entityType': entityType,
    'entityGlobalId': entityGlobalId,
    'operation': operation,
    'payloadVersion': payloadVersion,
    'payload': payload,
  };
}

final class SyncOperationResult {
  const SyncOperationResult(
    this.globalId,
    this.status, {
    this.error,
    this.errorCode,
    this.remoteVersion,
    this.remotePayload,
  });
  final String globalId;
  final String status;
  final String? error;
  final String? errorCode;
  final int? remoteVersion;
  final Map<String, Object?>? remotePayload;
  factory SyncOperationResult.fromJson(Map<String, Object?> j) =>
      SyncOperationResult(
        j['globalId'] as String,
        j['status'] as String,
        error: j['error'] as String?,
        errorCode: j['errorCode'] as String?,
        remoteVersion: (j['remoteVersion'] as num?)?.toInt(),
        remotePayload: j['remotePayload'] is Map
            ? Map<String, Object?>.from(j['remotePayload'] as Map)
            : null,
      );
}
