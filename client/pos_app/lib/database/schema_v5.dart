const List<String> schemaV5Statements = [
  r'''ALTER TABLE sync_queue ADD COLUMN error_category TEXT''',
  r'''ALTER TABLE sync_queue ADD COLUMN error_code TEXT''',
  r'''ALTER TABLE sync_queue ADD COLUMN requires_action INTEGER NOT NULL DEFAULT 0 CHECK(requires_action IN(0,1))''',
  r'''UPDATE sync_queue SET error_category=CASE WHEN next_attempt_at IS NOT NULL THEN 'NETWORK_ERROR' ELSE 'UNSUPPORTED_OPERATION' END,error_code='LegacyUnclassified',requires_action=CASE WHEN next_attempt_at IS NOT NULL THEN 0 ELSE 1 END WHERE status='Error' AND error_category IS NULL''',
  r'''CREATE INDEX ix_sync_queue_error_category ON sync_queue(error_category,status)''',
];
