final class SyncPullChange {
  const SyncPullChange({required this.cursor,required this.entityType,required this.entityGlobalId,required this.operation,required this.version,required this.changedAt,required this.payload});
  final int cursor; final String entityType; final String entityGlobalId; final String operation; final int version; final DateTime changedAt; final Map<String,Object?> payload;
  factory SyncPullChange.fromJson(Map<String,Object?> j)=>SyncPullChange(cursor:(j['cursor'] as num).toInt(),entityType:j['entityType'] as String,entityGlobalId:j['entityGlobalId'] as String,operation:j['operation'] as String,version:(j['version'] as num).toInt(),changedAt:DateTime.parse(j['changedAt'] as String).toUtc(),payload:Map<String,Object?>.from(j['payload'] as Map));
}
final class SyncPullBatch {
  const SyncPullBatch({required this.nextCursor,required this.hasMore,required this.changes,required this.serverTime});
  final int nextCursor; final bool hasMore; final List<SyncPullChange> changes; final DateTime serverTime;
  factory SyncPullBatch.fromJson(Map<String,Object?> j)=>SyncPullBatch(nextCursor:(j['nextCursor'] as num).toInt(),hasMore:j['hasMore'] as bool,changes:(j['changes'] as List).map((e)=>SyncPullChange.fromJson(Map<String,Object?>.from(e as Map))).toList(),serverTime:DateTime.parse(j['serverTime'] as String).toUtc());
}
